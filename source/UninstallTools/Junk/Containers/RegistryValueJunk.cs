/*
    Copyright (c) 2017 Marcin Szeniak (https://github.com/Klocman/)
    Apache License Version 2.0
*/

using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using Klocman.Extensions;
using Klocman.Tools;
using Microsoft.Win32;

namespace UninstallTools.Junk.Containers
{
    public class RegistryValueJunk : RegistryKeyJunk
    {
        public RegistryValueJunk(string containingKeyPath, string valueName, ApplicationUninstallerEntry application,
            IJunkCreator source) : base(containingKeyPath, application, source)
        {
            ValueName = valueName;
        }

        public string ValueName { get; }

        /// <summary>
        /// If not null, overrides ValueName in GetDisplayName
        /// </summary>
        public string DisplayValueName { get; set; }

        public override void Backup(string backupDirectory)
        {
            using var key = OpenRegKey();
            if (key == null)
                throw new IOException($"Registry key '{FullRegKeyPath}' could not be opened for backup.");

            var valueKind = key.GetValueKind(ValueName);
            var value = key.GetValue(ValueName, null, RegistryValueOptions.DoNotExpandEnvironmentNames);
            if (value == null)
                throw new IOException($"Registry value '{ValueName}' at '{FullRegKeyPath}' could not be read.");

            var dir = CreateBackupDirectory(backupDirectory);
            var fileName = PathTools.SanitizeFileName(string.Concat(FullRegKeyPath, " - ", ValueName)
                                                            .TrimStart('\\').Replace('.', '_')) + ".reg";
            RegistryTools.ExportRegistryValue(Path.Combine(dir, fileName), FullRegKeyPath, ValueName,
                valueKind, value);
        }

        public override string GetDisplayName()
        {
            return base.GetDisplayName() + " => " + (DisplayValueName ?? ValueName);
        }

        public override void Delete()
        {
            using (var key = RegistryTools.OpenRegistryKey(FullRegKeyPath, true))
            {
                key?.DeleteValue(ValueName);
            }
        }
    }
}