<?php
/*
  參數為欲抓取的日期，如 2015-12-05。
*/
date_default_timezone_set('Asia/Taipei');
libxml_use_internal_errors(true);
$keyword = urlencode('年');
$button = urlencode('查詢');
$sel_judword = urlencode('常用字別');
$dbname = 'judgements-development';
$dbuser = 'root';
$password = 'P@ssw0rd';

$court_json_content = file_get_contents("./courts.json");
$courts_array = json_decode($court_json_content, true);

$dsn = "mysql:host=127.0.0.1;dbname={$dbname}";
$dbh = new PDO($dsn, $dbuser, $password, array(PDO::MYSQL_ATTR_INIT_COMMAND => "SET NAMES utf8;"));

$sdate = new DateTime($argv[1]);
$edate = new DateTime($argv[1]);
$sdate -> modify('-1 day');

$sdate_string = ltrim($sdate -> format('Ymd'), '0');
$edate_string = ltrim($edate -> format('Ymd'), '0');

foreach ($courts_array as $court) {
    $court_string = strtolower(urlencode($court['name']));
    foreach ($court['departments'] as $department) {
        $url = "http://jirs.judicial.gov.tw/FJUD/FJUDQRY02_1.aspx?&v_court={$court['code']}+{$court_string}&v_sys={$department['code']}&jud_year=&jud_case=&jud_no=&jud_no_end=&jud_title=&keyword=&sdate={$sdate_string}&edate={$edate_string}&page=1&searchkw={$keyword}&jmain=&cw=0";
        error_log($url);

        $curl = curl_init($url);
        curl_setopt($curl, CURLOPT_REFERER, $url);
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        $content = curl_exec($curl);
        curl_close($curl);
        if (!preg_match('#本次查詢結果共([0-9]*)筆#', $content, $matches)) {
            error_log("{$court['name']} {$department['name']} has no record");
            continue;
        }
        $count = $matches[1];
        if (!preg_match('#FJUDQRY03_1\.aspx\?id=[0-9]*&([^"]*)#', $content, $matches)){
            error_log('page seems errror.');
            continue;
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
                error_log('cannot find link');
                continue;
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
            $court_code = explode(' ', $ret['v_court'])[0];
            $court_name = explode(' ', $ret['v_court'])[1];
            $date_string = explode(',', $ret['jrecno'])[3];
            $datetime = new DateTime($date_string);
            $date_string = $datetime->format("Y-m-d");
            $content = preg_replace('#<script(.*?)>(.*?)</script>#is', '', $content);
            $doc = new DOMDocument;
            $doc->loadHTML($content);
            $pre_dom = $doc->getElementsByTagNAme('pre');
            $judgement_content = $html = $pre_dom->item(0)->nodeValue;
            $td_dom = $doc->getElementsByTagNAme('td');
            $reason = $td_dom->item(10)->nodeValue;
            $identify = $court_code . '-' . str_replace(",","-",$ret['jrecno']);
            $now = new DateTime();
            $now = $now->format("Y-m-d H:i:s");
            switch ($ret['v_sys']) {
                case 'V':
                    $department = '民事';
                    break;
                case 'C':
                    $department = '刑事';
                    break;
                case 'A':
                    $department = '行政';
                    break;
                case 'P':
                    $department = '公懲';
                    break;
                default:
                    $department = null;
                    break;
            }
            // $record = array(
            //     $identify,
            //     $court_code,
            //     $court_name,
            //     $ret['jyear'],
            //     $ret['jcase'],
            //     $ret['jno'],
            //     $department,
            //     $ret['jcheck'],
            //     $reason,
            //     $judgement_content,
            //     $date_string,
            //     $now,
            //     $now
            // );
            $sql = "
               INSERT INTO
                  `judgements`
               SET
                  identify = :identify,
                  court_code = :court_code,
                  court_name = :court_name,
                  year = :year,
                  jcase = :jcase,
                  jno = :jno,
                  department = :department,
                  jcheck = :jcheck,
                  reason = :reason,
                  content = :content,
                  published_at = :published_at,
                  created_at = :created_at,
                  updated_at = :updated_at
               ON DUPLICATE KEY UPDATE
                  identify = :identify,
                  court_code = :court_code,
                  court_name = :court_name,
                  year = :year,
                  jcase = :jcase,
                  jno = :jno,
                  department = :department,
                  jcheck = :jcheck,
                  reason = :reason,
                  content = :content,
                  published_at = :published_at,
                  updated_at = :updated_at
            ";

            $sth = $dbh->prepare($sql);
            $sth->bindValue('identify', $identify , PDO::PARAM_STR);
            $sth->bindValue('court_code', $court_code , PDO::PARAM_STR);
            $sth->bindValue('court_name', $court_name , PDO::PARAM_STR);
            $sth->bindValue('year', $year , PDO::PARAM_INT);
            $sth->bindValue('jcase', $ret['jcase'] , PDO::PARAM_STR);
            $sth->bindValue('jno', $ret['jno'] , PDO::PARAM_INT);
            $sth->bindValue('department', $department , PDO::PARAM_STR);
            $sth->bindValue('jcheck', $ret['jcheck'] , PDO::PARAM_STR);
            $sth->bindValue('reason', $reason , PDO::PARAM_STR);
            $sth->bindValue('content', $judgement_content , PDO::PARAM_STR);
            $sth->bindValue('published_at', $date_string , PDO::PARAM_STR);
            $sth->bindValue('updated_at', $now , PDO::PARAM_STR);
            $sth->bindValue('created_at', $now , PDO::PARAM_STR);
            $sth->execute();
            // $file_name = "output/{$court_code}-{$ret['v_sys']}-{$ret['jdate']}-{$ret['jyear']}-{$ret['jcase']}-{$ret['jno']}-{$ret['jcheck']}";
            // file_put_contents($file_name, $content);
        }
    }
}
