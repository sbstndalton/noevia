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

/**
 * The model manager holds the Docker socket (docs/research-master-container.md). Block a deploy
 * where it runs without MODEL_LOADER_TOKEN, where web lacks the matching token, or where the
 * Diary sidecar shares a network with it (so it could resolve `model-loader`). Names only; the
 * token value is compared, never printed. A configuration without model-loader passes.
 */
function serviceEnv(array $settings): array {
    $env = [];
    foreach ($settings['environment'] ?? [] as $key => $value) {
        if (is_string($key)) { $env[$key] = is_scalar($value) ? (string)$value : ''; continue; }
        if (is_string($value)) { $pair = explode('=', $value, 2); $env[$pair[0]] = $pair[1] ?? ''; }
    }
    return $env;
}
function serviceNetworks(array $settings): array {
    $mode = $settings['network_mode'] ?? '';
    if (is_string($mode) && $mode !== '') return ["mode:$mode"];
    $networks = $settings['networks'] ?? null;
    if ($networks === null || $networks === []) return ['default'];
    return array_is_list($networks) ? array_values(array_map('strval', $networks)) : array_map('strval', array_keys($networks));
}
function modelLoaderBoundary(array $config, string $manager = 'model-loader', string $diary = 'diary'): array {
    $services = $config['services'] ?? [];
    if (!isset($services[$manager]) || !is_array($services[$manager])) return [];
    $errors = [];
    $token = serviceEnv($services[$manager])['MODEL_LOADER_TOKEN'] ?? '';
    if (strlen(trim($token)) < 32) $errors[] = "$manager: MODEL_LOADER_TOKEN is unset or shorter than 32 characters (openssl rand -hex 32).";
    if (isset($services['web']) && is_array($services['web']) && $token !== '') {
        $webToken = serviceEnv($services['web'])['MODEL_LOADER_TOKEN'] ?? '';
        if (!hash_equals($token, $webToken)) $errors[] = "web: MODEL_LOADER_TOKEN is missing or differs from $manager's.";
    }
    $managerNets = serviceNetworks($services[$manager]);
    if (in_array('mode:host', $managerNets, true)) $errors[] = "$manager: host networking exposes the socket-backed API.";
    if (isset($services[$diary]) && is_array($services[$diary])) {
        $diaryNets = serviceNetworks($services[$diary]);
        $shared = array_values(array_intersect($managerNets, $diaryNets));
        foreach ($diaryNets as $net) {
            if ($net === 'mode:host' || $net === "mode:service:$manager") $shared[] = $net;
        }
        if ($shared) $errors[] = "$diary: shares a network with $manager and could resolve it (" . implode(', ', array_unique($shared)) . ').';
    }
    return $errors;
}

/**
 * noevia#2226: a current Core with CODE_EGRESS_PORT set requires the native egress profile, and this check
 * refuses an installation without it. Web itself stops at startup only for bad syntax or a key directory or
 * file that fails its ownership checks; a missing service boots into a logged outage. Key names only in messages. Rolling back to an older image restores the check.php
 * that shipped beside it, because that image still uses its in-process proxy.
 */
function nativeEgressProfile(array $config): array {
    $web = $config['services']['web'] ?? null;
    if (!is_array($web)) return [];
    $we = serviceEnv($web);
    $port = trim($we['CODE_EGRESS_PORT'] ?? '');
    if ($port === '' || $port === '0') return [];
    $errors = [];
    $native = $config['services']['egress-rs'] ?? null;
    if (!preg_match('/^[1-9][0-9]{0,4}$/', $port) || (int)$port > 65535) return ['CODE_EGRESS_PORT is not a valid port.'];
    if (!is_array($native)) return ['CODE_EGRESS_PORT is set but the egress-rs service is missing (noevia#2226): see deploy/examples/code-egress-rust.override.yml.'];
    $ne = serviceEnv($native);
    // As Core reads them: an empty value takes the default, then the value is trimmed.
    $read = static fn(string $key, string $default): string => trim(($we[$key] ?? '') === '' ? $default : $we[$key]);
    $impl = $read('CODE_EGRESS_IMPL', 'rust');
    $host = $read('CODE_EGRESS_RUST_HOST', 'egress-rs-code');
    if ($impl !== 'rust') $errors[] = 'CODE_EGRESS_IMPL must be rust.';
    if (($ne['CODE_EGRESS_PORT'] ?? '') !== $port) $errors[] = 'web and egress-rs CODE_EGRESS_PORT differ.';
    $bind = $ne['CODE_EGRESS_BIND'] ?? '';
    if ($bind === '' || $host !== $bind) $errors[] = 'CODE_EGRESS_RUST_HOST does not name the egress-rs CODE_EGRESS_BIND.';
    $aliases = $native['networks']['code']['aliases'] ?? [];
    if ($bind !== '' && !in_array($bind, is_array($aliases) ? $aliases : [], true)) $errors[] = 'egress-rs CODE_EGRESS_BIND is not its alias on the code network.';
    if (!array_key_exists('code', (array)($web['networks'] ?? []))) $errors[] = 'web must be on the code network to reach egress-rs.';
    if (!empty($native['ports'])) $errors[] = 'egress-rs must not publish ports.';
    foreach (['CODE_EGRESS_KEY_UID', 'CODE_EGRESS_KEY_GID'] as $key) {
        if (!preg_match('/^(0|[1-9][0-9]{0,9})$/', $we[$key] ?? '')) $errors[] = "$key must be set on web.";
    }
    if (($we['CODE_EGRESS_KEY_GID'] ?? '') === '0') $errors[] = 'CODE_EGRESS_KEY_GID must not be 0.';
    foreach (['CODE_EGRESS_KEY_UID', 'CODE_EGRESS_KEY_GID'] as $key) if ((int)($we[$key] ?? 0) >= 0xffffffff) $errors[] = "$key is out of range.";
    if (!in_array($we['CODE_EGRESS_KEY_GID'] ?? '', array_map('strval', (array)($native['group_add'] ?? [])), true)) $errors[] = 'egress-rs group_add must include CODE_EGRESS_KEY_GID, or it cannot read the key.';
    if (($we['CODE_EGRESS_KEY_UID'] ?? '') !== ($ne['CODE_EGRESS_CONTROL_KEY_UID'] ?? null) || ($we['CODE_EGRESS_KEY_GID'] ?? '') !== ($ne['CODE_EGRESS_CONTROL_KEY_GID'] ?? null)) $errors[] = 'web and egress-rs key owner settings differ.';
    $file = $we['CODE_EGRESS_CONTROL_KEY_FILE'] ?? '';
    if ($file === '' || $file !== ($ne['CODE_EGRESS_CONTROL_KEY_FILE'] ?? '')) { $errors[] = 'CODE_EGRESS_CONTROL_KEY_FILE must be set and equal on web and egress-rs.'; return $errors; }
    $mount = static function (array $service) use ($file): ?array {
        foreach ($service['volumes'] ?? [] as $v) if (is_array($v) && ($v['target'] ?? '') === dirname($file)) return $v;
        return null;
    };
    $wm = $mount($web); $nm = $mount($native);
    if (!$wm || !$nm || ($wm['type'] ?? '') !== 'bind' || ($nm['type'] ?? '') !== 'bind' || ($wm['source'] ?? '') === '' || ($wm['source'] ?? '') !== ($nm['source'] ?? '')) $errors[] = 'web and egress-rs must bind the same control key directory.';
    elseif (!empty($wm['read_only']) || empty($nm['read_only'])) $errors[] = 'the control key directory must be writable on web and read-only on egress-rs.';
    // Compose renders create_host_path: false as an empty bind block, so only an explicit true is refused.
    elseif (($wm['bind']['create_host_path'] ?? false) === true || ($nm['bind']['create_host_path'] ?? false) === true) $errors[] = 'the control key directory must be prepared in advance (create_host_path: false).';
    if ($wm) foreach ($config['services'] as $name => $service) {
        if ($name === 'web' || $name === 'egress-rs' || !is_array($service)) continue;
        foreach ($service['volumes'] ?? [] as $v) {
            if (is_array($v) && (($v['source'] ?? '') === ($wm['source'] ?? null) || ($v['target'] ?? '') === dirname($file))) $errors[] = "the control key directory must not be mounted into $name.";
        }
    }
    return $errors;
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
        $errors = array_merge(validateMounts($config), modelLoaderBoundary($config), nativeEgressProfile($config));
        if ($errors) { foreach ($errors as $error) fwrite(STDERR, "BLOCKED: $error\n"); return 1; }
        echo "PASS: resolved writable mounts do not expose the protected boot directory/device.\n";
        if (isset($config['services']['model-loader'])) echo "PASS: model-loader is token-gated and unreachable from the Diary sidecar.\n";
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
