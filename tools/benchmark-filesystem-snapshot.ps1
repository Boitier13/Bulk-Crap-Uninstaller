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

function Get-BaselineEntryCount {
    param([string]$DirectoryPath)
    # Immediate-child enumeration without collecting metadata or sorting.
    $items = [IO.Directory]::GetFileSystemEntries($DirectoryPath)
    return $items.Length
}

function Get-Snapshot {
    param([string]$DirectoryPath)

    $entries = New-Object 'System.Collections.Generic.List[string]'
    $allPaths = New-Object 'System.Collections.Generic.List[string]'
    $allPaths.Add($DirectoryPath)

    foreach ($childPath in [IO.Directory]::GetFileSystemEntries($DirectoryPath)) {
        $allPaths.Add($childPath)
    }

    foreach ($itemPath in $allPaths) {
        $attributes = [IO.File]::GetAttributes($itemPath)
        $isDirectory = (($attributes -band [IO.FileAttributes]::Directory) -ne 0)
        $creationTicks = [IO.File]::GetCreationTimeUtc($itemPath).Ticks
        $writeTicks = [IO.File]::GetLastWriteTimeUtc($itemPath).Ticks
        $length = 0L

        if (-not $isDirectory) {
            $length = (New-Object IO.FileInfo($itemPath)).Length
        }

        $kind = if ($isDirectory) { 'D' } else { 'F' }
        $entries.Add(('{0}|{1}|{2}|{3}|{4}|{5}' -f $itemPath, $kind, $creationTicks, $writeTicks, [int]$attributes, $length))
    }

    $array = $entries.ToArray()
    [Array]::Sort($array, [StringComparer]::OrdinalIgnoreCase)
    return $array
}

function Get-Median {
    param([double[]]$Values)
    $sorted = @($Values | Sort-Object)
    $middle = [int][Math]::Floor($sorted.Count / 2)
    if (($sorted.Count % 2) -eq 1) { return [double]$sorted[$middle] }
    return ([double]$sorted[$middle - 1] + [double]$sorted[$middle]) / 2.0
}

try {
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

        # Warm-up to reduce one-time runtime/JIT effects.
        [void](Get-BaselineEntryCount -DirectoryPath $testDir)
        [void](Get-Snapshot -DirectoryPath $testDir)

        $baselineTimes = New-Object 'System.Collections.Generic.List[double]'
        $snapshotTimes = New-Object 'System.Collections.Generic.List[double]'
        $revalidationTimes = New-Object 'System.Collections.Generic.List[double]'

        for ($run = 1; $run -le $Repetitions; $run++) {
            $watch = [Diagnostics.Stopwatch]::StartNew()
            $baselineCount = Get-BaselineEntryCount -DirectoryPath $testDir
            $watch.Stop()
            $baselineTimes.Add($watch.Elapsed.TotalMilliseconds)

            $watch.Restart()
            $snapshot = Get-Snapshot -DirectoryPath $testDir
            $watch.Stop()
            $snapshotTimes.Add($watch.Elapsed.TotalMilliseconds)

            $watch.Restart()
            $first = Get-Snapshot -DirectoryPath $testDir
            $second = Get-Snapshot -DirectoryPath $testDir
            $watch.Stop()
            $revalidationTimes.Add($watch.Elapsed.TotalMilliseconds)

            if ($baselineCount -ne $count -or $snapshot.Length -ne ($count + 1) -or
                -not [Linq.Enumerable]::SequenceEqual([string[]]$first, [string[]]$second, [StringComparer]::OrdinalIgnoreCase)) {
                throw "Résultat incohérent pour le jeu de $count fichiers."
            }
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
