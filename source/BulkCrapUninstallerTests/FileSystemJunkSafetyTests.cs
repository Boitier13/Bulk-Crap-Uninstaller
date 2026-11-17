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

        private static string CreateTemporaryDirectory()
        {
            var path = System.IO.Path.Combine(System.IO.Path.GetTempPath(),
                "BCU-FileSystemJunkTests-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(path);
            return path;
        }
    }
}