# Copyright (c) 2026
# Compare the exact legacy string snapshot (PR #4) with the typed snapshot (PR #6).
# Windows PowerShell 5.1 / PowerShell 7. No BCU uninstall or cleanup is performed.
# The script only creates and removes its own uniquely named directory under %TEMP%.

[CmdletBinding()]
param(
    [int[]]$FileCounts = @(100, 1000, 5000),
    [ValidateRange(3, 20)]
    [int]$Repetitions = 7
)

$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ("BCU-Snapshot-Compare-" + [guid]::NewGuid().ToString('N'))
$results = New-Object System.Collections.Generic.List[object]

function Get-Median {
    param([double[]]$Values)
    $sorted = @($Values | Sort-Object)
    $middle = [int][Math]::Floor($sorted.Count / 2)
    if (($sorted.Count % 2) -eq 1) { return [double]$sorted[$middle] }
    return ([double]$sorted[$middle - 1] + [double]$sorted[$middle]) / 2.0
}

$source = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;

public static class BcuSnapshotComparison
{
    // PR #4: original string-based snapshot algorithm.
    private static string[] CaptureLegacy(DirectoryInfo directory)
    {
        var entries = new List<string>();
        AddLegacyEntry(directory, entries);

        foreach (FileSystemInfo child in directory.GetFileSystemInfos())
            AddLegacyEntry(child, entries);

        entries.Sort(StringComparer.OrdinalIgnoreCase);
        return entries.ToArray();
    }

    private static void AddLegacyEntry(FileSystemInfo entry, ICollection<string> entries)
    {
        entry.Refresh();
        if (!entry.Exists)
            throw new FileNotFoundException("An item disappeared during snapshot capture.", entry.FullName);

        bool isDirectory = entry is DirectoryInfo;
        long length = entry is FileInfo ? ((FileInfo)entry).Length : 0L;

        entries.Add(string.Join("|",
            entry.FullName,
            isDirectory ? "D" : "F",
            entry.CreationTimeUtc.Ticks,
            entry.LastWriteTimeUtc.Ticks,
            (int)entry.Attributes,
            length));
    }

    // PR #6: typed entries, sorted by path and compared field by field.
    private static SnapshotEntry[] CaptureTyped(DirectoryInfo directory)
    {
        SnapshotEntry rootEntry = CreateTypedEntry(directory);
        FileSystemInfo[] children = directory.GetFileSystemInfos();

        var entries = new SnapshotEntry[children.Length + 1];
        entries[0] = rootEntry;
        for (int i = 0; i < children.Length; i++)
            entries[i + 1] = CreateTypedEntry(children[i]);

        Array.Sort(entries, SnapshotEntryPathComparer.Instance);
        return entries;
    }

    private static SnapshotEntry CreateTypedEntry(FileSystemInfo entry)
    {
        entry.Refresh();
        if (!entry.Exists)
            throw new FileNotFoundException("An item disappeared during snapshot capture.", entry.FullName);

        bool isDirectory = entry is DirectoryInfo;
        long length = entry is FileInfo ? ((FileInfo)entry).Length : 0L;

        return new SnapshotEntry(
            entry.FullName,
            isDirectory,
            entry.CreationTimeUtc.Ticks,
            entry.LastWriteTimeUtc.Ticks,
            entry.Attributes,
            length);
    }

    private static bool TypedSnapshotsMatch(SnapshotEntry[] first, SnapshotEntry[] second)
    {
        if (first.Length != second.Length)
            return false;

        for (int i = 0; i < first.Length; i++)
            if (!first[i].Equals(second[i]))
                return false;

        return true;
    }

    private static bool ImplementationsAgree(string[] legacy, SnapshotEntry[] typed)
    {
        if (legacy.Length != typed.Length)
            return false;

        // Compare as sorted sets. The legacy algorithm sorts serialized rows,
        // while the typed algorithm sorts by path; their ordering can differ
        // for prefix-related filenames even when the captured data is identical.
        var typedRows = new string[typed.Length];
        for (int i = 0; i < typed.Length; i++)
            typedRows[i] = typed[i].ToLegacyRow();

        Array.Sort(typedRows, StringComparer.OrdinalIgnoreCase);
        for (int i = 0; i < legacy.Length; i++)
            if (!String.Equals(legacy[i], typedRows[i], StringComparison.OrdinalIgnoreCase))
                return false;

        return true;
    }

    public static void ValidateImplementations(string path, int expectedFiles)
    {
        var directory = new DirectoryInfo(path);
        string[] legacy = CaptureLegacy(directory);
        SnapshotEntry[] typed = CaptureTyped(directory);

        if (legacy.Length != expectedFiles + 1 || typed.Length != expectedFiles + 1)
            throw new InvalidOperationException("Unexpected snapshot entry count.");

        if (!ImplementationsAgree(legacy, typed))
            throw new InvalidOperationException("Legacy and typed snapshots contain different data.");

        if (!TypedSnapshotsMatch(typed, CaptureTyped(directory)))
            throw new InvalidOperationException("Two typed snapshots of an unchanged directory differ.");

        if (!LegacySnapshotsMatch(legacy, CaptureLegacy(directory)))
            throw new InvalidOperationException("Two legacy snapshots of an unchanged directory differ.");
    }

    private static bool LegacySnapshotsMatch(string[] first, string[] second)
    {
        if (first.Length != second.Length)
            return false;
        for (int i = 0; i < first.Length; i++)
            if (!String.Equals(first[i], second[i], StringComparison.OrdinalIgnoreCase))
                return false;
        return true;
    }

    public static double MeasureLegacyOne(string path)
    {
        var directory = new DirectoryInfo(path);
        var watch = Stopwatch.StartNew();
        string[] snapshot = CaptureLegacy(directory);
        watch.Stop();
        GC.KeepAlive(snapshot);
        return watch.Elapsed.TotalMilliseconds;
    }

    public static double MeasureTypedOne(string path)
    {
        var directory = new DirectoryInfo(path);
        var watch = Stopwatch.StartNew();
        SnapshotEntry[] snapshot = CaptureTyped(directory);
        watch.Stop();
        GC.KeepAlive(snapshot);
        return watch.Elapsed.TotalMilliseconds;
    }

    public static double MeasureLegacyTwo(string path)
    {
        var directory = new DirectoryInfo(path);
        var watch = Stopwatch.StartNew();
        string[] first = CaptureLegacy(directory);
        string[] second = CaptureLegacy(directory);
        if (!LegacySnapshotsMatch(first, second))
            throw new InvalidOperationException("Legacy snapshots differ.");
        watch.Stop();
        GC.KeepAlive(second);
        return watch.Elapsed.TotalMilliseconds;
    }

    public static double MeasureTypedTwo(string path)
    {
        var directory = new DirectoryInfo(path);
        var watch = Stopwatch.StartNew();
        SnapshotEntry[] first = CaptureTyped(directory);
        SnapshotEntry[] second = CaptureTyped(directory);
        if (!TypedSnapshotsMatch(first, second))
            throw new InvalidOperationException("Typed snapshots differ.");
        watch.Stop();
        GC.KeepAlive(second);
        return watch.Elapsed.TotalMilliseconds;
    }

    private struct SnapshotEntry : IEquatable<SnapshotEntry>
    {
        public SnapshotEntry(string path, bool isDirectory, long creationTicks,
            long lastWriteTicks, FileAttributes attributes, long length)
        {
            Path = path;
            IsDirectory = isDirectory;
            CreationTicks = creationTicks;
            LastWriteTicks = lastWriteTicks;
            Attributes = attributes;
            Length = length;
        }

        public string Path;
        private bool IsDirectory;
        private long CreationTicks;
        private long LastWriteTicks;
        private FileAttributes Attributes;
        private long Length;

        public bool Equals(SnapshotEntry other)
        {
            return StringComparer.OrdinalIgnoreCase.Equals(Path, other.Path)
                && IsDirectory == other.IsDirectory
                && CreationTicks == other.CreationTicks
                && LastWriteTicks == other.LastWriteTicks
                && Attributes == other.Attributes
                && Length == other.Length;
        }

        public string ToLegacyRow()
        {
            return string.Join("|", Path, IsDirectory ? "D" : "F",
                CreationTicks, LastWriteTicks, (int)Attributes, Length);
        }
    }

    private sealed class SnapshotEntryPathComparer : IComparer<SnapshotEntry>
    {
        public static readonly SnapshotEntryPathComparer Instance = new SnapshotEntryPathComparer();

        public int Compare(SnapshotEntry x, SnapshotEntry y)
        {
            return StringComparer.OrdinalIgnoreCase.Compare(x.Path, y.Path);
        }
    }
}
'@

try {
    Add-Type -TypeDefinition $source -Language CSharp
    New-Item -ItemType Directory -Path $root | Out-Null

    Write-Host "Dossier temporaire : $root"
    Write-Host "Preparation des fichiers de test (hors chronometrage)..."

    foreach ($count in $FileCounts) {
        if ($count -lt 1) { throw "Le nombre de fichiers doit etre positif : $count" }

        $testDir = Join-Path $root ("files-{0}" -f $count)
        New-Item -ItemType Directory -Path $testDir | Out-Null
        $payload = [byte[]](1..128)

        for ($i = 1; $i -le $count; $i++) {
            $filePath = Join-Path $testDir ("item-{0:D6}.bin" -f $i)
            [IO.File]::WriteAllBytes($filePath, $payload)
        }

        [BcuSnapshotComparison]::ValidateImplementations($testDir, $count)

        # Warm up both paths before recording results.
        [void][BcuSnapshotComparison]::MeasureLegacyOne($testDir)
        [void][BcuSnapshotComparison]::MeasureTypedOne($testDir)
        [void][BcuSnapshotComparison]::MeasureLegacyTwo($testDir)
        [void][BcuSnapshotComparison]::MeasureTypedTwo($testDir)

        $legacyOne = New-Object 'System.Collections.Generic.List[double]'
        $typedOne = New-Object 'System.Collections.Generic.List[double]'
        $legacyTwo = New-Object 'System.Collections.Generic.List[double]'
        $typedTwo = New-Object 'System.Collections.Generic.List[double]'

        for ($run = 1; $run -le $Repetitions; $run++) {
            # Alternate order to reduce systematic first/second measurement bias.
            if (($run % 2) -eq 1) {
                $legacyOne.Add([BcuSnapshotComparison]::MeasureLegacyOne($testDir))
                $typedOne.Add([BcuSnapshotComparison]::MeasureTypedOne($testDir))
                $legacyTwo.Add([BcuSnapshotComparison]::MeasureLegacyTwo($testDir))
                $typedTwo.Add([BcuSnapshotComparison]::MeasureTypedTwo($testDir))
            }
            else {
                $typedOne.Add([BcuSnapshotComparison]::MeasureTypedOne($testDir))
                $legacyOne.Add([BcuSnapshotComparison]::MeasureLegacyOne($testDir))
                $typedTwo.Add([BcuSnapshotComparison]::MeasureTypedTwo($testDir))
                $legacyTwo.Add([BcuSnapshotComparison]::MeasureLegacyTwo($testDir))
            }
        }

        $oldOne = Get-Median -Values $legacyOne.ToArray()
        $newOne = Get-Median -Values $typedOne.ToArray()
        $oldTwo = Get-Median -Values $legacyTwo.ToArray()
        $newTwo = Get-Median -Values $typedTwo.ToArray()

        $results.Add([pscustomobject]@{
            NombreFichiers = $count
            Repetitions = $Repetitions
            AncienSnapshotMs = [Math]::Round($oldOne, 3)
            NouveauSnapshotMs = [Math]::Round($newOne, 3)
            GainSnapshotPct = if ($oldOne -gt 0) { [Math]::Round((1 - ($newOne / $oldOne)) * 100, 1) } else { $null }
            AncienneRevalidationDeuxSnapshotsMs = [Math]::Round($oldTwo, 3)
            NouvelleRevalidationDeuxSnapshotsMs = [Math]::Round($newTwo, 3)
            GainRevalidationPct = if ($oldTwo -gt 0) { [Math]::Round((1 - ($newTwo / $oldTwo)) * 100, 1) } else { $null }
        })

        Write-Host ("{0} fichiers : ancien {1} ms -> optimise {2} ms | deux captures : {3} ms -> {4} ms" -f
            $count, [Math]::Round($oldOne, 3), [Math]::Round($newOne, 3),
            [Math]::Round($oldTwo, 3), [Math]::Round($newTwo, 3))
    }

    $desktop = [Environment]::GetFolderPath('Desktop')
    if ([string]::IsNullOrWhiteSpace($desktop) -or -not (Test-Path -LiteralPath $desktop)) {
        $desktop = (Get-Location).Path
    }
    $csvPath = Join-Path $desktop ("BCU-snapshot-comparison-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $results | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

    Write-Host ""
    Write-Host "Comparaison des medianes :"
    $results | Format-Table -AutoSize
    Write-Host "CSV enregistre : $csvPath"
    Write-Host "Aucune suppression BCU n'a ete executee."
}
finally {
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force
        Write-Host "Dossier temporaire du benchmark nettoye : $root"
    }
}
