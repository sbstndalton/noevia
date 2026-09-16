<?php
/** Resolve writable Compose mounts on the Docker host. Never print configuration secrets. */
declare(strict_types=1);

function resolveHostPath(string $input): string {
    if ($input === '' || $input[0] !== '/' || str_contains($input, "\0")) throw new RuntimeException('Absolute host path required');
    $todo = explode('/', $input); $parts = []; $links = 0;
    while ($todo) {
        $part = array_shift($todo);
        if ($part === '' || $part === '.') continue;
        if ($part === '..') { array_pop($parts); continue; }
        $probe = '/' . implode('/', array_merge($parts, [$part]));
        if (is_link($probe)) {
            if (++$links > 40) throw new RuntimeException('Symlink loop');
            $target = readlink($probe);
            if ($target === false) throw new RuntimeException('Unreadable symlink');
            if (str_starts_with($target, '/')) $parts = [];
            $todo = array_merge(explode('/', $target), $todo);
        } else {
            $parts[] = $part;
        }
    }
    return '/' . implode('/', $parts);
}
function insidePath(string $path, string $parent): bool {
    return $path === $parent || str_starts_with($path, rtrim($parent, '/') . '/');
}
function validateMounts(array $config, string $protected = '/boot'): array {
    $protected = resolveHostPath($protected); $errors = [];
    foreach ($config['services'] ?? [] as $service => $settings) {
        foreach ($settings['volumes'] ?? [] as $mount) {
            if (!is_array($mount)) { $errors[] = "$service: unresolved mount; use Compose config JSON."; continue; }
            if (($mount['type'] ?? '') !== 'bind' || ($mount['read_only'] ?? false) === true) continue;
            try {
                $source = $mount['source'] ?? null;
                if (!is_string($source)) throw new RuntimeException('Missing source');
                $resolved = resolveHostPath($source);
                if (insidePath($resolved, $protected) || insidePath($protected, $resolved)) {
                    $errors[] = "$service: writable bind exposes the protected boot directory.";
                    continue;
                }
                $boot = @stat($protected); $parent = @stat(dirname($protected));
                // Device identity catches an alias mount of Unraid's boot device.
                // Ordinary Linux /boot may be part of the root filesystem.
                if ($boot !== false && $parent !== false && $boot['dev'] !== $parent['dev']) {
                    $ancestor = $resolved;
                    while (!file_exists($ancestor) && $ancestor !== dirname($ancestor)) $ancestor = dirname($ancestor);
                    $sourceStat = @stat($ancestor);
                    if ($sourceStat === false) throw new RuntimeException('Unreadable source');
                    if ($sourceStat['dev'] === $boot['dev']) $errors[] = "$service: writable bind resides on the protected boot device.";
                }
            } catch (Throwable $e) { $errors[] = "$service: could not resolve a writable bind safely."; }
        }
    }
    foreach ($config['volumes'] ?? [] as $name => $volume) {
        if (!empty($volume['driver_opts'])) $errors[] = "$name: volume driver options need separate host verification; use a normal bind for local paths.";
    }
    return $errors;
}
/**
 * Compare the env-var NAMES the resolved `web` service declares against the set
 * the repository ships. The live Unraid Compose file is a third copy that does
 * not auto-sync (docs/deployment.md), and a key dropped while copying it by hand
 * fails silently: MCP simply never turns on. Names only — a value is a secret or
 * a deployment choice, and neither is read or printed here.
 *
 * Advisory, never blocking. An operator may legitimately have pruned a key they
 * do not use, and refusing to start a working deployment over an optional knob
 * would be a worse failure than the drift it is warning about.
 */
function envKeyDrift(array $config, string $expectedFile, string $service = 'web'): array {
    $raw = @file_get_contents($expectedFile);
    if ($raw === false) return [];
    $expected = array_values(array_filter(array_map('trim', explode("\n", $raw)), static fn($k) => $k !== ''));
    if (!$expected) return [];

    $settings = $config['services'][$service] ?? null;
    if (!is_array($settings)) return ["$service: service not present in the resolved configuration."];
    $environment = $settings['environment'] ?? [];
    $present = [];
    // `docker compose config --format json` emits a map, but the list form
    // (`- KEY=value`) reaches here from a hand-written file resolved elsewhere.
    foreach ($environment as $key => $value) {
        if (is_string($key)) { $present[] = $key; continue; }
        if (is_string($value)) $present[] = explode('=', $value, 2)[0];
    }
    $missing = array_values(array_diff($expected, $present));
    if (!$missing) return [];
    return ["$service: missing env keys versus the repository: " . implode(', ', $missing)];
}

function preflightMain(array $arguments): int {
    try {
        if (count($arguments) < 2 || $arguments[0] !== '--config-json') throw new RuntimeException('Input required');
        $expectedFile = '';
        if (count($arguments) === 4 && $arguments[2] === '--expect-env') $expectedFile = $arguments[3];
        elseif (count($arguments) !== 2) throw new RuntimeException('Unknown arguments');
        $raw = @file_get_contents($arguments[1] === '-' ? 'php://stdin' : $arguments[1]);
        $config = json_decode($raw, true, 512, JSON_THROW_ON_ERROR);
        if (!is_array($config) || empty($config['services']) || !is_array($config['services'])) throw new RuntimeException('No services');
        $errors = validateMounts($config);
        if ($errors) { foreach ($errors as $error) fwrite(STDERR, "BLOCKED: $error\n"); return 1; }
        echo "PASS: resolved writable mounts do not expose the protected boot directory/device.\n";
        if ($expectedFile !== '') {
            $drift = envKeyDrift($config, $expectedFile);
            foreach ($drift as $warning) fwrite(STDERR, "WARN: $warning\n");
            if (!$drift) echo "PASS: the web service declares every env key the repository ships.\n";
        }
        return 0;
    } catch (Throwable $e) {
        fwrite(STDERR, "BLOCKED: could not validate Compose JSON. Run on the Docker host with --config-json FILE (or - for stdin).\n");
        return 1;
    }
}
if (realpath($_SERVER['SCRIPT_FILENAME'] ?? '') === __FILE__) exit(preflightMain(array_slice($argv, 1)));
