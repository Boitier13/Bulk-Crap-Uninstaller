/*
    Copyright (c) 2017 Marcin Szeniak (https://github.com/Klocman/)
    Apache License Version 2.0
*/

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Klocman.Tools;
using Microsoft.VisualBasic.FileIO;

namespace UninstallTools.Junk.Containers
{
    public class FileSystemJunk : JunkResultBase
    {
        private readonly string[] _initialSnapshot;
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

            string[] currentSnapshot;
            try
            {
                currentSnapshot = CaptureSnapshot(Path);
            }
            catch (Exception ex)
            {
                throw new IOException("The leftover could not be rechecked immediately before deletion, so it was not deleted.", ex);
            }

            if (!_initialSnapshot.SequenceEqual(currentSnapshot, StringComparer.OrdinalIgnoreCase))
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

        private static string[] CaptureSnapshot(FileSystemInfo path)
        {
            var entries = new List<string>();
            AddSnapshotEntry(path, entries);

            if (path is DirectoryInfo directory)
            {
                // A shallow snapshot is intentionally used to keep scans inexpensive.
                // It detects additions/removals in the target directory and changes to
                // its immediate children (including child-directory timestamps).
                foreach (var child in directory.GetFileSystemInfos())
                    AddSnapshotEntry(child, entries);
            }

            entries.Sort(StringComparer.OrdinalIgnoreCase);
            return entries.ToArray();
        }

        private static void AddSnapshotEntry(FileSystemInfo entry, ICollection<string> snapshot)
        {
            entry.Refresh();
            if (!entry.Exists)
                throw new FileNotFoundException("A leftover item disappeared while its state was being recorded.", entry.FullName);

            var isDirectory = entry is DirectoryInfo;
            var length = entry is FileInfo file ? file.Length : 0L;
            snapshot.Add(string.Join("|",
                entry.FullName,
                isDirectory ? "D" : "F",
                entry.CreationTimeUtc.Ticks,
                entry.LastWriteTimeUtc.Ticks,
                (int)entry.Attributes,
                length));
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