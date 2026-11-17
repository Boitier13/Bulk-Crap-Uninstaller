using Klocman.Tools;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace BulkCrapUninstallerTests
{
    [TestClass]
    public class PathBoundarySafetyTests
    {
        [TestMethod]
        public void SubPathIsInsideBasePath_AcceptsChildDirectory()
        {
            Assert.IsTrue(PathTools.SubPathIsInsideBasePath(
                @"C:\Program Files", @"C:\Program Files\Demo", false, true));
        }

        [TestMethod]
        public void SubPathIsInsideBasePath_RejectsSiblingWithSamePrefix()
        {
            Assert.IsFalse(PathTools.SubPathIsInsideBasePath(
                @"C:\Program Files", @"C:\Program Files-old\Demo", false, true));
        }

        [TestMethod]
        public void SubPathIsInsideBasePath_HandlesExactMatchExplicitly()
        {
            Assert.IsTrue(PathTools.SubPathIsInsideBasePath(
                @"C:\Windows", @"C:\Windows", false, true));
            Assert.IsFalse(PathTools.SubPathIsInsideBasePath(
                @"C:\Windows", @"C:\Windows", false, false));
        }

        [TestMethod]
        public void SubPathIsInsideBasePath_AcceptsEitherSlashStyle()
        {
            Assert.IsTrue(PathTools.SubPathIsInsideBasePath(
                @"C:/Windows", @"C:\Windows\System32", false, true));
        }
    }
}
