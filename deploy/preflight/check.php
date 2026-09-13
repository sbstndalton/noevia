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
function preflightMain(array $arguments): int {
    try {
        if (count($arguments) !== 2 || $arguments[0] !== '--config-json') throw new RuntimeException('Input required');
        $raw = @file_get_contents($arguments[1] === '-' ? 'php://stdin' : $arguments[1]);
        $config = json_decode($raw, true, 512, JSON_THROW_ON_ERROR);
        if (!is_array($config) || empty($config['services']) || !is_array($config['services'])) throw new RuntimeException('No services');
        $errors = validateMounts($config);
        if ($errors) { foreach ($errors as $error) fwrite(STDERR, "BLOCKED: $error\n"); return 1; }
        echo "PASS: resolved writable mounts do not expose the protected boot directory/device.\n";
        return 0;
    } catch (Throwable $e) {
        fwrite(STDERR, "BLOCKED: could not validate Compose JSON. Run on the Docker host with --config-json FILE (or - for stdin).\n");
        return 1;
    }
}
if (realpath($_SERVER['SCRIPT_FILENAME'] ?? '') === __FILE__) exit(preflightMain(array_slice($argv, 1)));
