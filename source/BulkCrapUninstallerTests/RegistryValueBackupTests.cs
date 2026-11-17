using System;
using System.IO;
using System.Text;
using Klocman.Tools;
using Microsoft.Win32;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace BulkCrapUninstallerTests
{
    [TestClass]
    public class RegistryValueBackupTests
    {
        private string _directory;

        [TestInitialize]
        public void Initialize()
        {
            _directory = Path.Combine(Path.GetTempPath(), "BCU-RegistryBackupTests-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(_directory);
        }

        [TestCleanup]
        public void Cleanup()
        {
            if (Directory.Exists(_directory))
                Directory.Delete(_directory, true);
        }

        [TestMethod]
        public void ExportRegistryValue_PreservesStringTypesAndEscaping()
        {
            var path = Path.Combine(_directory, "string.reg");
            RegistryTools.ExportRegistryValue(path, @"HKEY_CURRENT_USER\Software\BCUTest", "DisplayName",
                RegistryValueKind.String, "A path\\with \"quotes\"");

            var content = File.ReadAllText(path, Encoding.Unicode);
            StringAssert.Contains(content, "\"DisplayName\"=\"A path\\\\with \\\"quotes\\\"\"");
        }

        [TestMethod]
        public void ExportRegistryValue_PreservesNumericAndBinaryTypes()
        {
            var dwordPath = Path.Combine(_directory, "dword.reg");
            RegistryTools.ExportRegistryValue(dwordPath, @"HKEY_CURRENT_USER\Software\BCUTest", "Count",
                RegistryValueKind.DWord, 42);
            StringAssert.Contains(File.ReadAllText(dwordPath, Encoding.Unicode), "\"Count\"=dword:0000002a");

            var qwordPath = Path.Combine(_directory, "qword.reg");
            RegistryTools.ExportRegistryValue(qwordPath, @"HKEY_CURRENT_USER\Software\BCUTest", "LargeCount",
                RegistryValueKind.QWord, 42L);
            StringAssert.Contains(File.ReadAllText(qwordPath, Encoding.Unicode),
                "\"LargeCount\"=hex(b):2a,00,00,00,00,00,00,00");

            var binaryPath = Path.Combine(_directory, "binary.reg");
            RegistryTools.ExportRegistryValue(binaryPath, @"HKEY_CURRENT_USER\Software\BCUTest", "Payload",
                RegistryValueKind.Binary, new byte[] { 0, 1, 254, 255 });
            StringAssert.Contains(File.ReadAllText(binaryPath, Encoding.Unicode),
                "\"Payload\"=hex:00,01,fe,ff");
        }

        [TestMethod]
        public void ExportRegistryValue_PreservesMultiStringAndDefaultValueName()
        {
            var multiPath = Path.Combine(_directory, "multi.reg");
            RegistryTools.ExportRegistryValue(multiPath, @"HKEY_CURRENT_USER\Software\BCUTest", "Items",
                RegistryValueKind.MultiString, new[] { "one", "two" });
            StringAssert.Contains(File.ReadAllText(multiPath, Encoding.Unicode),
                "\"Items\"=hex(7):6f,00,6e,00,65,00,00,00,74,00,77,00,6f,00,00,00,00,00");

            var defaultPath = Path.Combine(_directory, "default.reg");
            RegistryTools.ExportRegistryValue(defaultPath, @"HKEY_CURRENT_USER\Software\BCUTest", "",
                RegistryValueKind.String, "Default");
            StringAssert.Contains(File.ReadAllText(defaultPath, Encoding.Unicode), "@=\"Default\"");
        }

        [TestMethod]
        public void ExportRegistryValue_RejectsUnsupportedKinds()
        {
            Assert.ThrowsException<NotSupportedException>(() =>
                RegistryTools.ExportRegistryValue(Path.Combine(_directory, "unknown.reg"),
                    @"HKEY_CURRENT_USER\Software\BCUTest", "Unknown", RegistryValueKind.Unknown, new byte[0]));
        }
    }
}
