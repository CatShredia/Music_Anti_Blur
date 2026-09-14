namespace MusicAntiBlur.Api.Config;

public static class DotEnv
{
    public static void LoadFromAncestors(string startDirectory)
    {
        var dir = startDirectory;
        for (var i = 0; i < 8 && dir is not null; i++)
        {
            var path = Path.Combine(dir, ".env");
            if (File.Exists(path))
            {
                Load(path);
                return;
            }

            dir = Directory.GetParent(dir)?.FullName;
        }
    }

    public static void Load(string path)
    {
        foreach (var raw in File.ReadAllLines(path))
        {
            var line = raw.Trim();
            if (line.Length == 0 || line.StartsWith('#'))
            {
                continue;
            }

            var eq = line.IndexOf('=');
            if (eq <= 0)
            {
                continue;
            }

            var key = line[..eq].Trim();
            var value = line[(eq + 1)..].Trim();
            if (value.Length >= 2 &&
                ((value[0] == '"' && value[^1] == '"') || (value[0] == '\'' && value[^1] == '\'')))
            {
                value = value[1..^1];
            }

            if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable(key)))
            {
                Environment.SetEnvironmentVariable(key, value);
            }
        }
    }
}
