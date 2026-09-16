<?php
declare(strict_types=1);
require __DIR__ . '/check.php';
function verify(bool $value, string $message): void { if (!$value) throw new RuntimeException($message); }
function configFor(string $source, bool $readonly = false): array {
    return ['services'=>['web'=>['volumes'=>[['type'=>'bind','source'=>$source,'read_only'=>$readonly]]]]];
}
$root = sys_get_temp_dir() . '/noevia-preflight-' . bin2hex(random_bytes(8));
mkdir($root, 0700); mkdir("$root/boot"); mkdir("$root/appdata");
symlink("$root/boot", "$root/alias"); symlink('boot', "$root/relative");
symlink('loop', "$root/loop");
try {
    foreach (["$root/boot", "$root/boot/future", "$root/alias/future", "$root/relative/future", $root, "$root/appdata/../boot/state"] as $source) {
        verify(count(validateMounts(configFor($source), "$root/boot")) > 0, 'Unsafe path accepted');
    }
    foreach (["$root/appdata", "$root/boot-backup", "$root/alias/../appdata", "$root/missing/../appdata"] as $source) {
        verify(validateMounts(configFor($source), "$root/boot") === [], 'Safe path rejected');
    }
    verify(validateMounts(configFor("$root/boot", true), "$root/boot") === [], 'Read-only mount rejected');
    verify(count(validateMounts(configFor("$root/loop"), "$root/boot")) > 0, 'Symlink loop accepted');
    verify(count(validateMounts(configFor('relative/state'))) > 0, 'Relative source accepted');
    verify(count(validateMounts(['services'=>['web'=>['volumes'=>['/boot:/data']]]])) > 0, 'Unresolved mount accepted');
    verify(validateMounts(['services'=>['web'=>['volumes'=>[['type'=>'volume','source'=>'web-state']]]]]) === [], 'Managed volume rejected');
    verify(count(validateMounts(['services'=>[], 'volumes'=>['state'=>['driver_opts'=>['device'=>'/boot']]]])) > 0, 'Driver bind bypass accepted');
    // ---- env-key drift (advisory) ----
    $expected = "$root/keys.txt";
    file_put_contents($expected, "MCP_SERVERS\nTAVILY_API_KEY\nUI_PORT\n");
    $withAll = ['services'=>['web'=>['environment'=>['MCP_SERVERS'=>'', 'TAVILY_API_KEY'=>'', 'UI_PORT'=>'8021']]]];
    verify(envKeyDrift($withAll, $expected) === [], 'Complete env set reported as drift');
    $missing = ['services'=>['web'=>['environment'=>['UI_PORT'=>'8021']]]];
    $drift = envKeyDrift($missing, $expected);
    verify(count($drift) === 1, 'Missing env keys not reported');
    verify(str_contains($drift[0], 'MCP_SERVERS') && str_contains($drift[0], 'TAVILY_API_KEY'), 'Drift message does not name the missing keys');
    // Values must never appear, only names.
    verify(!str_contains($drift[0], '8021'), 'Drift message leaked a value');
    $listForm = ['services'=>['web'=>['environment'=>['MCP_SERVERS=x', 'TAVILY_API_KEY=y', 'UI_PORT=8021']]]];
    verify(envKeyDrift($listForm, $expected) === [], 'List-form environment not understood');
    verify(envKeyDrift($withAll, "$root/absent.txt") === [], 'Absent expectation file treated as drift');
    verify(count(envKeyDrift(['services'=>['diary'=>[]]], $expected)) === 1, 'Missing web service not reported');
    unlink($expected);

    echo "PASS: direct/parent paths, symlink aliases, missing descendants, loops, read-only and managed volumes; env-key drift.\n";
} finally {
    foreach (['alias','relative','loop'] as $name) unlink("$root/$name");
    rmdir("$root/boot"); rmdir("$root/appdata"); rmdir($root);
}
