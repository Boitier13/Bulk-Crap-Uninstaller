/*
    Copyright (c) 2017 Marcin Szeniak (https://github.com/Klocman/)
    Apache License Version 2.0
*/

using System;
using System.Collections.Generic;
using System.IO;
using Klocman.Tools;
using Microsoft.VisualBasic.FileIO;

namespace UninstallTools.Junk.Containers
{
    public class FileSystemJunk : JunkResultBase
    {
        private readonly SnapshotEntry[] _initialSnapshot;
        private readonly Exception _snapshotError;

        public FileSystemJunk(FileSystemInfo path, ApplicationUninstallerEntry application, IJunkCreator source) : base(application, source)
        {
            Path = path ?? throw new ArgumentNullException(nameof(path));

            try
            {
                _initialSnapshot = CaptureSnapshot(path);
            }
            catch (Exception ex)
            {
                // Fail closed during deletion if the item's state could not be recorded.
                _snapshotError = ex;
            }
        }

        public FileSystemInfo Path { get; }

        public override void Backup(string backupDirectory)
        {
            // Items are deleted to the recycle bin
        }

        public override void Delete()
        {
            if (_snapshotError != null)
                throw new IOException("The leftover could not be safely checked when it was detected, so it was not deleted.", _snapshotError);

            SnapshotEntry[] currentSnapshot;
            try
            {
                currentSnapshot = CaptureSnapshot(Path);
            }
            catch (Exception ex)
            {
                throw new IOException("The leftover could not be rechecked immediately before deletion, so it was not deleted.", ex);
            }

            if (!SnapshotsMatch(_initialSnapshot, currentSnapshot))
                throw new IOException("The leftover has changed since it was detected. It was not deleted: " + Path.FullName);

            if (Path is DirectoryInfo)
                FileSystem.DeleteDirectory(Path.FullName, UIOption.OnlyErrorDialogs,
                    RecycleOption.SendToRecycleBin, UICancelOption.DoNothing);
            else if (Path is FileInfo)
                FileSystem.DeleteFile(Path.FullName, UIOption.OnlyErrorDialogs,
                    RecycleOption.SendToRecycleBin, UICancelOption.DoNothing);
            else
                throw new NotImplementedException("Unknown FileSystemInfo implementation");
        }

        private static SnapshotEntry[] CaptureSnapshot(FileSystemInfo path)
        {
            FileSystemInfo[] children = path is DirectoryInfo directory
                ? directory.GetFileSystemInfos()
                : Array.Empty<FileSystemInfo>();

            var entries = new SnapshotEntry[children.Length + 1];
            entries[0] = CreateSnapshotEntry(path);

            for (int i = 0; i < children.Length; i++)
                entries[i + 1] = CreateSnapshotEntry(children[i]);

            Array.Sort(entries, SnapshotEntryPathComparer.Instance);
            return entries;
        }

        private static SnapshotEntry CreateSnapshotEntry(FileSystemInfo entry)
        {
            entry.Refresh();
            if (!entry.Exists)
                throw new FileNotFoundException("A leftover item disappeared while its state was being recorded.", entry.FullName);

            var isDirectory = entry is DirectoryInfo;
            var length = entry is FileInfo file ? file.Length : 0L;

            return new SnapshotEntry(
                entry.FullName,
                isDirectory,
                entry.CreationTimeUtc.Ticks,
                entry.LastWriteTimeUtc.Ticks,
                entry.Attributes,
                length);
        }

        private static bool SnapshotsMatch(SnapshotEntry[] first, SnapshotEntry[] second)
        {
            if (first.Length != second.Length)
                return false;

            for (int i = 0; i < first.Length; i++)
            {
                if (!first[i].Equals(second[i]))
                    return false;
            }

            return true;
        }

        private readonly struct SnapshotEntry : IEquatable<SnapshotEntry>
        {
            public SnapshotEntry(string path, bool isDirectory, long creationTimeUtcTicks,
                long lastWriteTimeUtcTicks, FileAttributes attributes, long length)
            {
                Path = path;
                IsDirectory = isDirectory;
                CreationTimeUtcTicks = creationTimeUtcTicks;
                LastWriteTimeUtcTicks = lastWriteTimeUtcTicks;
                Attributes = attributes;
                Length = length;
            }

            public string Path { get; }
            private bool IsDirectory { get; }
            private long CreationTimeUtcTicks { get; }
            private long LastWriteTimeUtcTicks { get; }
            private FileAttributes Attributes { get; }
            private long Length { get; }

            public bool Equals(SnapshotEntry other)
            {
                return StringComparer.OrdinalIgnoreCase.Equals(Path, other.Path)
                    && IsDirectory == other.IsDirectory
                    && CreationTimeUtcTicks == other.CreationTimeUtcTicks
                    && LastWriteTimeUtcTicks == other.LastWriteTimeUtcTicks
                    && Attributes == other.Attributes
                    && Length == other.Length;
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

        public override string GetDisplayName()
        {
            return Path.FullName;
        }

        public override void Open()
        {
            if (Path.Exists)
                WindowsTools.OpenExplorerFocusedOnObject(Path.FullName);
            else
                throw new FileNotFoundException(null, Path.FullName);
        }
    }
}