# Copyright (c) 2026
# Non-destructive benchmark for the shallow FileSystemJunk snapshot algorithm.
# Compatible with Windows PowerShell 5.1 and PowerShell 7.
# Only creates and removes files inside its own uniquely named temporary directory.

[CmdletBinding()]
param(
    [int[]]$FileCounts = @(100, 1000, 5000),
    [ValidateRange(3, 20)]
    [int]$Repetitions = 5
)

$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ("BCU-Snapshot-Benchmark-" + [guid]::NewGuid().ToString('N'))
$results = New-Object System.Collections.Generic.List[object]

# Run the timed work in compiled .NET code, not in PowerShell loops.
# The snapshot implementation mirrors FileSystemJunk.CaptureSnapshot from PR #4.
$benchmarkSource = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;

public static class BcuSnapshotBenchmark
{
    private static string[] CaptureSnapshot(string directoryPath)
    {
        var entries = new List<string>();
        AddEntry(directoryPath, entries);

        foreach (var child in new DirectoryInfo(directoryPath).GetFileSystemInfos())
            AddEntry(child.FullName, entries);

        entries.Sort(StringComparer.OrdinalIgnoreCase);
        return entries.ToArray();
    }

    private static void AddEntry(string path, ICollection<string> entries)
    {
        FileSystemInfo entry = Directory.Exists(path)
            ? (FileSystemInfo)new DirectoryInfo(path)
            : new FileInfo(path);

        entry.Refresh();
        if (!entry.Exists)
            throw new FileNotFoundException("An item disappeared during snapshot capture.", path);

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

    public static double MeasureEnumeration(string path, int repetitions, out int entryCount)
    {
        var watch = new Stopwatch();
        entryCount = 0;
        for (int i = 0; i < repetitions; i++)
        {
            watch.Start();
            entryCount = Directory.GetFileSystemEntries(path).Length;
            watch.Stop();
        }
        return watch.Elapsed.TotalMilliseconds / repetitions;
    }

    public static double MeasureOneSnapshot(string path, int repetitions, out int entryCount)
    {
        var watch = new Stopwatch();
        entryCount = 0;
        for (int i = 0; i < repetitions; i++)
        {
            watch.Start();
            entryCount = CaptureSnapshot(path).Length;
            watch.Stop();
        }
        return watch.Elapsed.TotalMilliseconds / repetitions;
    }

    public static double MeasureTwoSnapshots(string path, int repetitions, out int entryCount)
    {
        var watch = new Stopwatch();
        entryCount = 0;
        for (int i = 0; i < repetitions; i++)
        {
            watch.Start();
            string[] first = CaptureSnapshot(path);
            string[] second = CaptureSnapshot(path);
            watch.Stop();

            if (first.Length != second.Length)
                throw new InvalidOperationException("Snapshot entry counts differ.");
            for (int j = 0; j < first.Length; j++)
                if (!String.Equals(first[j], second[j], StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("Snapshots differ.");
            entryCount = second.Length;
        }
        return watch.Elapsed.TotalMilliseconds / repetitions;
    }
}
'@

try {
    Add-Type -TypeDefinition $benchmarkSource -Language CSharp

    New-Item -ItemType Directory -Path $root | Out-Null
    Write-Host "Dossier temporaire : $root"
    Write-Host "Préparation des jeux de test (cette étape n'est pas chronométrée)..."

    foreach ($count in $FileCounts) {
        if ($count -lt 1) { throw "Le nombre de fichiers doit être positif : $count" }

        $testDir = Join-Path $root ("files-{0}" -f $count)
        New-Item -ItemType Directory -Path $testDir | Out-Null
        $payload = [byte[]](1..128)

        for ($i = 1; $i -le $count; $i++) {
            $filePath = Join-Path $testDir ("item-{0:D6}.bin" -f $i)
            [IO.File]::WriteAllBytes($filePath, $payload)
        }

        # Warm-up before collecting the measurements.
        $warmCount = 0
        [void][BcuSnapshotBenchmark]::MeasureEnumeration($testDir, 1, [ref]$warmCount)
        [void][BcuSnapshotBenchmark]::MeasureOneSnapshot($testDir, 1, [ref]$warmCount)
        [void][BcuSnapshotBenchmark]::MeasureTwoSnapshots($testDir, 1, [ref]$warmCount)

        $baselineTimes = New-Object 'System.Collections.Generic.List[double]'
        $snapshotTimes = New-Object 'System.Collections.Generic.List[double]'
        $revalidationTimes = New-Object 'System.Collections.Generic.List[double]'

        for ($run = 1; $run -le $Repetitions; $run++) {
            $entryCount = 0
            $baselineTimes.Add([BcuSnapshotBenchmark]::MeasureEnumeration($testDir, 1, [ref]$entryCount))
            if ($entryCount -ne $count) { throw "Énumération incohérente pour $count fichiers." }

            $snapshotTimes.Add([BcuSnapshotBenchmark]::MeasureOneSnapshot($testDir, 1, [ref]$entryCount))
            if ($entryCount -ne ($count + 1)) { throw "Snapshot incohérent pour $count fichiers." }

            $revalidationTimes.Add([BcuSnapshotBenchmark]::MeasureTwoSnapshots($testDir, 1, [ref]$entryCount))
            if ($entryCount -ne ($count + 1)) { throw "Revalidation incohérente pour $count fichiers." }
        }

        $baseMedian = Get-Median -Values $baselineTimes.ToArray()
        $snapMedian = Get-Median -Values $snapshotTimes.ToArray()
        $recheckMedian = Get-Median -Values $revalidationTimes.ToArray()

        $results.Add([pscustomobject]@{
            NombreFichiers = $count
            Repetitions = $Repetitions
            EnumerationSimpleMedianeMs = [Math]::Round($baseMedian, 3)
            SnapshotInitialMedianeMs = [Math]::Round($snapMedian, 3)
            RevalidationDeuxSnapshotsMedianeMs = [Math]::Round($recheckMedian, 3)
            SurcoutSnapshotVsEnumerationMs = [Math]::Round(($snapMedian - $baseMedian), 3)
            SurcoutSnapshotVsEnumerationPct = if ($baseMedian -gt 0) { [Math]::Round((($snapMedian / $baseMedian) - 1) * 100, 1) } else { $null }
        })

        Write-Host ("{0} fichiers : énumération {1} ms | snapshot {2} ms | deux snapshots {3} ms" -f $count, [Math]::Round($baseMedian, 3), [Math]::Round($snapMedian, 3), [Math]::Round($recheckMedian, 3))
    }

    $desktop = [Environment]::GetFolderPath('Desktop')
    if ([string]::IsNullOrWhiteSpace($desktop) -or -not (Test-Path -LiteralPath $desktop)) {
        $desktop = (Get-Location).Path
    }
    $csvPath = Join-Path $desktop ("BCU-snapshot-benchmark-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $results | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

    Write-Host ''
    Write-Host 'Résultats :'
    $results | Format-Table -AutoSize
    Write-Host "CSV enregistré : $csvPath"
    Write-Host 'Aucune suppression BCU n’a été exécutée.'
}
finally {
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force
        Write-Host "Dossier temporaire du benchmark nettoyé : $root"
    }
}
