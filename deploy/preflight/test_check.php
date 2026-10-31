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

    // ---- model-loader boundary (blocking) ----
    $tok = str_repeat('a', 64);
    $good = ['services'=>[
        'model-loader'=>['environment'=>['MODEL_LOADER_TOKEN'=>$tok], 'networks'=>['models'=>null]],
        'web'=>['environment'=>['MODEL_LOADER_TOKEN'=>$tok], 'networks'=>['default'=>null, 'models'=>null]],
        'diary'=>['networks'=>['default'=>null]]]];
    verify(modelLoaderBoundary($good) === [], 'Isolated, token-gated model-loader rejected');
    verify(modelLoaderBoundary(['services'=>['web'=>[]]]) === [], 'Config without model-loader rejected');
    $unset = $good; $unset['services']['model-loader']['environment'] = [];
    verify(count(modelLoaderBoundary($unset)) > 0, 'Unset token accepted');
    $short = $good; $short['services']['model-loader']['environment']['MODEL_LOADER_TOKEN'] = 'abc';
    verify(count(modelLoaderBoundary($short)) > 0, 'Short token accepted');
    $webless = $good; $webless['services']['web']['environment'] = [];
    verify(count(modelLoaderBoundary($webless)) > 0, 'Web without token accepted');
    $sharedNet = $good; $sharedNet['services']['diary']['networks'] = ['default'=>null, 'models'=>null];
    $msg = modelLoaderBoundary($sharedNet);
    verify(count($msg) === 1 && str_contains($msg[0], 'models'), 'Diary on the models network accepted');
    verify(!str_contains(implode('', modelLoaderBoundary($webless)), $tok), 'Boundary message leaked the token');
    $defaults = $good; unset($defaults['services']['model-loader']['networks'], $defaults['services']['diary']['networks']);
    verify(count(modelLoaderBoundary($defaults)) > 0, 'Both on the implicit default network accepted');
    $hostMode = $good; $hostMode['services']['diary']['network_mode'] = 'host';
    verify(count(modelLoaderBoundary($hostMode)) > 0, 'Diary host networking accepted');
    $listEnv = $good; $listEnv['services']['model-loader']['environment'] = ["MODEL_LOADER_TOKEN=$tok"];
    verify(modelLoaderBoundary($listEnv) === [], 'List-form token not understood');

    // ---- native egress profile (noevia#2226) ----
    $k = '/run/noevia-egress-control';
    $egress = ['services'=>[
        'web'=>['networks'=>['code'=>null],'environment'=>['CODE_EGRESS_PORT'=>'8040','CODE_EGRESS_RUST_HOST'=>'egress-rs-code','CODE_EGRESS_KEY_UID'=>'0','CODE_EGRESS_KEY_GID'=>'1006','CODE_EGRESS_CONTROL_KEY_FILE'=>"$k/current.key"],'volumes'=>[['type'=>'bind','source'=>'/keys','target'=>$k,'bind'=>['create_host_path'=>false]]]],
        'egress-rs'=>['environment'=>['CODE_EGRESS_PORT'=>'8040','CODE_EGRESS_BIND'=>'egress-rs-code','CODE_EGRESS_CONTROL_KEY_UID'=>'0','CODE_EGRESS_CONTROL_KEY_GID'=>'1006','CODE_EGRESS_CONTROL_KEY_FILE'=>"$k/current.key"],'group_add'=>['1006'],'networks'=>['code'=>['aliases'=>['egress-rs-code']]],'volumes'=>[['type'=>'bind','source'=>'/keys','target'=>$k,'read_only'=>true,'bind'=>['create_host_path'=>false]]]]]];
    verify(nativeEgressProfile($egress) === [], 'Complete native egress profile rejected');
    verify(nativeEgressProfile(['services'=>['web'=>['environment'=>[]]]]) === [], 'Unset port rejected');
    verify(nativeEgressProfile(['services'=>['web'=>['environment'=>['CODE_EGRESS_PORT'=>'0']]]]) === [], 'Disabled port rejected');
    $badPort = $egress; $badPort['services']['web']['environment']['CODE_EGRESS_PORT'] = '70000'; $badPort['services']['egress-rs']['environment']['CODE_EGRESS_PORT'] = '70000';
    verify(count(nativeEgressProfile($badPort)) > 0, 'Invalid port accepted');
    $blank = $egress; $blank['services']['web']['environment']['CODE_EGRESS_IMPL'] = ''; $blank['services']['web']['environment']['CODE_EGRESS_RUST_HOST'] = '';
    verify(nativeEgressProfile($blank) === [], 'Empty values Core defaults were rejected');
    $space = $egress; $space['services']['web']['environment']['CODE_EGRESS_RUST_HOST'] = ' ';
    verify(count(nativeEgressProfile($space)) > 0, 'A whitespace host that Core refuses was accepted');
    $noService = $egress; unset($noService['services']['egress-rs']);
    verify(count(nativeEgressProfile($noService)) > 0, 'Port set without egress-rs accepted');
    foreach ([
        fn($c)=>[$c['services']['web']['environment']['CODE_EGRESS_IMPL'] = 'node', $c][1],
        fn($c)=>[$c['services']['egress-rs']['environment']['CODE_EGRESS_PORT'] = '8041', $c][1],
        fn($c)=>[$c['services']['web']['environment']['CODE_EGRESS_RUST_HOST'] = 'egress', $c][1],
        fn($c)=>[$c['services']['egress-rs']['networks']['code']['aliases'] = [], $c][1],
        fn($c)=>[$c['services']['egress-rs']['ports'] = ['8040:8040'], $c][1],
        function($c){ unset($c['services']['web']['environment']['CODE_EGRESS_KEY_UID']); return $c; },
        fn($c)=>[$c['services']['web']['environment']['CODE_EGRESS_KEY_GID'] = '0', $c][1],
        fn($c)=>[$c['services']['egress-rs']['environment']['CODE_EGRESS_CONTROL_KEY_GID'] = '7', $c][1],
        function($c){ unset($c['services']['web']['environment']['CODE_EGRESS_CONTROL_KEY_FILE']); return $c; },
        fn($c)=>[$c['services']['web']['volumes'] = [], $c][1],
        fn($c)=>[$c['services']['egress-rs']['group_add'] = [], $c][1],
        fn($c)=>[$c['services']['web']['networks'] = ['default'=>null], $c][1],
        fn($c)=>[$c['services']['web']['environment']['CODE_EGRESS_KEY_UID'] = '4294967295', $c][1],
        fn($c)=>[$c['services']['egress-rs']['volumes'][0]['bind']['create_host_path'] = true, $c][1],
        fn($c)=>[$c['services']['egress-rs']['volumes'][0]['source'] = '/other', $c][1],
        fn($c)=>[$c['services']['web']['volumes'][0]['read_only'] = true, $c][1],
        fn($c)=>[$c['services']['egress-rs']['volumes'][0]['read_only'] = false, $c][1],
    ] as $i => $breaks) verify(count(nativeEgressProfile($breaks($egress))) > 0, "Broken native egress profile $i accepted");

    echo "PASS: model-loader boundary; direct/parent paths, symlink aliases, missing descendants, loops, read-only and managed volumes; env-key drift.\n";
} finally {
    foreach (['alias','relative','loop'] as $name) unlink("$root/$name");
    rmdir("$root/boot"); rmdir("$root/appdata"); rmdir($root);
}
