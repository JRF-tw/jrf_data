<?php
/*
  參數為欲抓取的日期，如 2015-12-05。
*/
date_default_timezone_set('Asia/Taipei');
$keyword = urlencode('號');
$button = urlencode('查詢');
$sel_judword = urlencode('常用字別');


$court_json_content = file_get_contents("./courts.json");
$courts_array = json_decode($court_json_content, true);

$sdate = new DateTime($argv[1]);
$edate = new DateTime($argv[1]);
$edate -> modify('+1 day');
$sdate -> modify('-1911 years');
$edate -> modify('-1911 years');


$sdate_string = ltrim($sdate -> format('Ymd'), '0');
$sdate_year = ltrim($sdate -> format('Y'), '0');
$sdate_month = ltrim($sdate -> format('m'), '0');
$sdate_day = ltrim($sdate -> format('d'), '0');
$edate_string = ltrim($edate -> format('Ymd'), '0');
$edate_year = ltrim($edate -> format('Y'), '0');
$edate_month = ltrim($edate -> format('m'), '0');
$edate_day = ltrim($edate -> format('d'), '0');

foreach ($courts_array as $court) {
    $court_string = urlencode($court['name']);
    foreach ($court['departments'] as $department) {
        $url = "http://jirs.judicial.gov.tw/FJUD/FJUDQRY02_1.aspx?&v_court={$court['code']}+{$court_string}&v_sys={$department['code']}&jud_year=&jud_case=&jud_no=&jud_title={$keyword}&keyword=&sdate={$sdate_string}&edate={$edate_string}&page=1&searchkw=";
        error_log($url);
        $curl = curl_init($url);
        curl_setopt($curl, CURLOPT_REFERER, $url);
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        $content = curl_exec($curl);
        curl_close($curl);
        if (!preg_match('#本次查詢結果共([0-9]*)筆#', $content, $matches)) {
            var_dump($content);
            error_log("{$court['name']} {$department['name']} has no record");
            continue;
        }
        $count = $matches[1];
        if (!preg_match('#FJUDQRY03_1\.aspx\?id=[0-9]*&([^"]*)#', $content, $matches)){
            var_dump($content);
            throw new Exception('test2');
        }
        $param = $matches[1];
        for ($j = 1; $j <= $count; $j ++) {
            $case_url = "http://jirs.judicial.gov.tw/FJUD/FJUDQRY03_1.aspx?id={$j}&{$param}";
            error_log("{$j}/{$count} {$case_url}");
            $curl = curl_init($case_url);
            curl_setopt($curl, CURLOPT_REFERER, $url);
            curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
            $content = curl_exec($curl);
            curl_close($curl);

            if (!preg_match('#href="([^"]*)">友善列印#', $content, $matches)) {
                var_dump($content);
                throw new Exception('test3');
            }
            $print_url = $matches[1];
            $query = parse_url($print_url, PHP_URL_QUERY);
            parse_str($query, $ret);
            /*
            ["jrecno"]=>
            string(26) "104,司促,2243,20150130,1"
            ["v_court"]=>
            string(28) "TPD 臺灣臺北地方法院"
            ["v_sys"]=>
            string(1) "V"
            ["jyear"]=>
            string(3) "104"
            ["jcase"]=>
            string(6) "司促"
            ["jno"]=>
            string(4) "2243"
            ["jdate"]=>
            string(7) "1040130"
            ["jcheck"]=>
            string(1) "1"
             */
            $court = explode(' ', $ret['v_court'])[0];
            $file_name = "output/{$court}-{$ret['v_sys']}-{$ret['jdate']}-{$ret['jyear']}-{$ret['jcase']}-{$ret['jno']}-{$ret['jcheck']}";
            file_put_contents($file_name, $content);
        }
    }
}
