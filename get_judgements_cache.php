<?php

date_default_timezone_set('Asia/Taipei');

if (!isset($argv[1]) || strlen($argv[1]) !== 4) {
    error_log('please provide target year, ex. php -q get_judgements_cache.php 2011');
    exit();
}
$targetYear = intval($argv[1]);
$errorLogFile = __DIR__ . '/cache/' . $targetYear . '.log';

if (file_exists(__DIR__ . '/cache/' . $targetYear . '.done')) {
    error_log("target year {$targetYear} was completed\n", 3, $errorLogFile);
    exit();
}

exec('/bin/ps aux | grep get_judgements_cache.php', $console);
$lineCount = 0;
foreach ($console AS $line) {
    if (substr($line, -29) === 'get_judgements_cache.php ' . $targetYear) {
        ++$lineCount;
        if ($lineCount >= 2) {
            error_log(date('Y-m-d H:i:s') . "|previous process found, die\n", 3, $errorLogFile);
            exit();
        }
    }
}

$blockCount = 0;
$proxy = 'proxy.hinet.net:80';
$keyword = urlencode('年');
$url = "http://jirs.judicial.gov.tw/FJUD/FJUDQRY02_1.aspx";
$courts = json_decode(file_get_contents(__DIR__ . '/courts.json'), true);

$dateBegin = strtotime($targetYear . '-01-01');
$dateEnd = strtotime($targetYear . '-12-31');
while ($dateBegin <= $dateEnd) {
    $cachePath = __DIR__ . '/cache/' . date('Y/m/d', $dateBegin);
    if (!file_exists($cachePath)) {
        mkdir($cachePath, 0777, true);
    }
    $dateNext = $dateBegin + 86400;
    $dateLabel = date('Ymd', $dateBegin) . '~' . date('Ymd', $dateNext);

    foreach ($courts as $court) {
        foreach ($court['divisions'] AS $division) {
            $param = "&v_court={$court['code']}+" . urlencode($court['name']) . "&v_sys={$division['code']}&jud_year=&jud_case=&jud_no=&jud_no_end=&jud_title=&keyword={$keyword}&sdate=" . date('Ymd', $dateBegin) . "&edate=" . date('Ymd', $dateNext) . "&page=1&searchkw={$keyword}&jmain=&cw=0";
            $urlDecoded = urldecode($url . '?' . $param);
            $md5 = md5($urlDecoded);
            $cachedFile = $cachePath . '/list_' . $md5;
            if (!file_exists($cachedFile)) {
                error_log(date('Y-m-d H:i:s') . "|[{$dateLabel}]fetching list {$urlDecoded}\n", 3, $errorLogFile);
                $listFetched = false;
                while (false === $listFetched) {
                    $curl = curl_init($url);
                    curl_setopt($curl, CURLOPT_REFERER, $url);
                    curl_setopt($curl, CURLOPT_PROXY, $proxy);
                    curl_setopt($curl, CURLOPT_FORBID_REUSE, true);
                    curl_setopt($curl, CURLOPT_POSTFIELDS, $param);
                    curl_setopt($curl, CURLOPT_COOKIESESSION, true);
                    curl_setopt($curl, CURLOPT_USERAGENT, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/47.0.2526.106 Safari/537.36');
                    curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
                    curl_setopt($curl, CURLOPT_HEADER, 1);
                    $response = curl_exec($curl);
                    $header_size = curl_getinfo($curl, CURLINFO_HEADER_SIZE);
                    $header = substr($response, 0, $header_size);
                    $content = substr($response, $header_size);
                    if (empty($header) || false !== strpos($content, 'Object moved') || false !== strpos($header, 'Service Unavailable')) {
                        if (++$blockCount >= 5) {
                            error_log(date('Y-m-d H:i:s') . "|blocked more than 5 times, sleep for 1 min\n", 3, $errorLogFile);
                            sleep(60);
                            $blockCount = 0;
                        } else {
                            error_log(date('Y-m-d H:i:s') . "|block detected in list! sleep for 2 sec.\n", 3, $errorLogFile);
                            sleep(2);
                        }
                    } else {
                        $blockCount = 0;
                        error_log($header, 3, $errorLogFile);
                        file_put_contents($cachedFile, $content);
                        $listFetched = true;
                    }
                }
            } else {
                $content = file_get_contents($cachedFile);
            }

            if (!preg_match('#(\d+)\s+筆 / 每頁\s+20\s+筆 / 共\s+\d+\s+頁 / 現在第#m', $content, $matches)) {
                continue;
            }
            $count = $matches[1];
            if (preg_match('#本次查詢結果共([0-9]*)筆#', $content, $matches)) {
                $count = $matches[1];
            }
            if (!preg_match('#FJUDQRY03_1\.aspx\?id=[0-9]*&([^"]*)#', $content, $matches)) {
                continue;
            }
            $param = $matches[1];
            for ($j = 1; $j <= $count; $j ++) {
                $caseFetched = false;
                while (false === $caseFetched) {
                    $case_url = "http://jirs.judicial.gov.tw/FJUD/FJUDQRY03_1.aspx";
                    $urlDecoded = urldecode($case_url . "?id={$j}&{$param}");
                    $md5 = md5($urlDecoded);
                    $cachedFile = $cachePath . '/case_' . $md5;
                    if (!file_exists($cachedFile)) {
                        $curl = curl_init($case_url);
                        error_log(date('Y-m-d H:i:s') . "|[{$dateLabel}]fetching case {$j}/{$count}\n", 3, $errorLogFile);
                        curl_setopt($curl, CURLOPT_PROXY, $proxy);
                        curl_setopt($curl, CURLOPT_FORBID_REUSE, true);
                        curl_setopt($curl, CURLOPT_VERBOSE, true);
                        curl_setopt($curl, CURLOPT_POSTFIELDS, "id={$j}&{$param}");
                        curl_setopt($curl, CURLOPT_URL, $case_url);
                        curl_setopt($curl, CURLOPT_REFERER, 'http://jirs.judicial.gov.tw/FJUD/FJUDQRY02_1.aspx');
                        curl_setopt($curl, CURLOPT_USERAGENT, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/47.0.2526.106 Safari/537.36');
                        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
                        curl_setopt($curl, CURLOPT_HEADER, 1);
                        $response = curl_exec($curl);
                        $header_size = curl_getinfo($curl, CURLINFO_HEADER_SIZE);
                        $header = substr($response, 0, $header_size);
                        $content = substr($response, $header_size);
                        if (empty($header) || false !== strpos($content, 'Object moved') || false !== strpos($header, 'Service Unavailable')) {
                            if (++$blockCount >= 5) {
                                error_log(date('Y-m-d H:i:s') . "|blocked more than 5 times, sleep for 1 min\n", 3, $errorLogFile);
                                sleep(60);
                                $blockCount = 0;
                            } else {
                                error_log(date('Y-m-d H:i:s') . "|block detected in case! sleep for 2 sec.\n", 3, $errorLogFile);
                                sleep(2);
                            }
                        } else {
                            $blockCount = 0;
                            error_log($header, 3, $errorLogFile);
                            $caseFetched = true;
                            file_put_contents($cachedFile, $content);
                        }
                    } else {
                        $caseFetched = true;
                    }
                }
            }
        }
    }

    $dateBegin = $dateNext + 86400;
}
file_put_contents(__DIR__ . '/cache/' . $targetYear . '.done', '1');
