using System;
using System.IO;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using UninstallTools.Junk.Containers;

namespace BulkCrapUninstallerTests
{
    [TestClass]
    public class FileSystemJunkSafetyTests
    {
        [TestMethod]
        public void Delete_RefusesDirectoryWhenNewChildWasAdded()
        {
            var directory = CreateTemporaryDirectory();
            try
            {
                var junk = new FileSystemJunk(new DirectoryInfo(directory), null, null);
                var addedFile = System.IO.Path.Combine(directory, "created-after-detection.txt");
                File.WriteAllText(addedFile, "keep this file");

                Assert.ThrowsException<IOException>(() => junk.Delete());
                Assert.IsTrue(Directory.Exists(directory));
                Assert.IsTrue(File.Exists(addedFile));
            }
            finally
            {
                if (Directory.Exists(directory))
                    Directory.Delete(directory, true);
            }
        }

        [TestMethod]
        public void Delete_RefusesFileWhenItsContentsChanged()
        {
            var directory = CreateTemporaryDirectory();
            var filePath = System.IO.Path.Combine(directory, "leftover.txt");
            try
            {
                File.WriteAllText(filePath, "original");
                var junk = new FileSystemJunk(new FileInfo(filePath), null, null);
                File.WriteAllText(filePath, "modified after detection");

                Assert.ThrowsException<IOException>(() => junk.Delete());
                Assert.IsTrue(File.Exists(filePath));
                Assert.AreEqual("modified after detection", File.ReadAllText(filePath));
            }
            finally
            {
                if (Directory.Exists(directory))
                    Directory.Delete(directory, true);
            }
        }

        [TestMethod]
        public void Delete_AllowsUnchangedFile()
        {
            var directory = CreateTemporaryDirectory();
            var filePath = System.IO.Path.Combine(directory, "unchanged-leftover.txt");
            try
            {
                File.WriteAllText(filePath, "unchanged content");
                var junk = new FileSystemJunk(new FileInfo(filePath), null, null);

                junk.Delete();

                Assert.IsFalse(File.Exists(filePath));
            }
            finally
            {
                if (Directory.Exists(directory))
                    Directory.Delete(directory, true);
            }
        }

        [TestMethod]
        public void Delete_RefusesDirectoryWhenImmediateChildChanges()
        {
            var directory = CreateTemporaryDirectory();
            var childPath = System.IO.Path.Combine(directory, "child.txt");
            try
            {
                File.WriteAllText(childPath, "original");
                var junk = new FileSystemJunk(new DirectoryInfo(directory), null, null);

                File.WriteAllText(childPath, "changed");
                File.SetLastWriteTimeUtc(childPath, DateTime.UtcNow.AddMinutes(2));

                Assert.ThrowsException<IOException>(() => junk.Delete());
                Assert.IsTrue(Directory.Exists(directory));
                Assert.AreEqual("changed", File.ReadAllText(childPath));
            }
            finally
            {
                if (Directory.Exists(directory))
                    Directory.Delete(directory, true);
            }
        }

        [TestMethod]
        public void Delete_AllowsUnchangedDirectoryWithImmediateChild()
        {
            var directory = CreateTemporaryDirectory();
            var childPath = System.IO.Path.Combine(directory, "child.txt");
            try
            {
                File.WriteAllText(childPath, "unchanged content");
                var junk = new FileSystemJunk(new DirectoryInfo(directory), null, null);

                junk.Delete();

                Assert.IsFalse(Directory.Exists(directory));
                Assert.IsFalse(File.Exists(childPath));
            }
            finally
            {
                if (Directory.Exists(directory))
                    Directory.Delete(directory, true);
            }
        }

        private static string CreateTemporaryDirectory()
        {
            var path = System.IO.Path.Combine(System.IO.Path.GetTempPath(),
                "BCU-FileSystemJunkTests-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(path);
            return path;
        }
    }
}
