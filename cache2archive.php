<?php

$archivePath = __DIR__ . '/archive';
$count = false;
$keys = new stdClass();
foreach (glob(__DIR__ . '/cache/*/*/*') AS $rawPath) {
    if (is_dir($rawPath)) {
        $parts = explode('/', $rawPath);
        if (false === $count) {
            $count = count($parts);
            $keys->y = $count - 3;
            $keys->m = $count - 2;
            $keys->d = $count - 1;
        }
        $yPath = "{$archivePath}/{$parts[$keys->y]}";
        if (!file_exists($yPath)) {
            mkdir($yPath, 0777, true);
        }
        $fileTime = mktime(0, 0, 0, $parts[$keys->m], $parts[$keys->d], $parts[$keys->y]);
        $nextTime = $fileTime + 86400;
        $archiveFile = $yPath . '/' . date('Ymd', $fileTime) . '-' . date('d', $nextTime) . '.tar.gz';
        exec("/bin/tar -czf {$archiveFile} {$rawPath}");
    }
}