#!/usr/bin/env ruby

require 'open-uri'
require 'uri'
require 'iconv'
require 'nokogiri'
require 'json'
require 'mechanize'
require 'mysql2'
require 'date'
require 'cgi'
# require 'charlock_holmes'

def read_db_config
  file = File.read('./db.json')
  return JSON.parse(file)
end

def init_db
  db_config = read_db_config()
  return Mysql2::Client.new(:host => db_config['host'], :username => db_config['username'], :password => db_config['password'], :database => db_config['database'])
end

def get_courts
  file = File.read('./courts.json')
  return JSON.parse(file)
end

def write_json(filename, content)
  File.open(filename,"w") do |f|
    f.write(JSON.pretty_generate(content))
  end
end

def sleep_random_second
  seconds = Random.rand(5..15)
  puts "sleep #{seconds} seconds..."
  sleep(seconds)
end

def get_date_section
  date1 = Date.parse(ARGV[0]) - 1
  date2 = Date.parse(ARGV[0])
  date1 = date1.strftime('%Y%m%d')
  date2 = date2.strftime('%Y%m%d')
  return date1, date1
end

def get_html(url)
  page = open(url)
  html = Nokogiri::HTML(page.read)
end

def get_nccharset(agent)
  raw_html = agent.get(URI.parse("http://jirs.judicial.gov.tw/FJUD/FJUDQRY01_1.aspx"))
  html = Nokogiri::HTML(raw_html.body)
  html.css("input[name='nccharset']").first.attr('value')
end

def get_actual_date(date_string)
  year = date_string[0..-5].to_i + 1911
  Date.parse(year.to_s + date_string[-4..-1]).strftime('%Y-%m-%d')
end

def main
  keyword = URI.escape('年')
  db = init_db()
  courts = get_courts()
  date1, date2 = get_date_section()
  courts.each do |court|
    sleep_random_second()
    court_string = URI.escape(court['name']).downcase
    court['divisions'].each do |division|
      url = "http://jirs.judicial.gov.tw/FJUD/FJUDQRY02_1.aspx?&v_court=#{court['code']}+#{court_string}&v_sys=#{division['code']}&jud_year=&jud_case=&jud_no=&jud_no_end=&jud_title=&keyword=&sdate=#{date1}&edate=#{date2}&page=1&searchkw=#{keyword}&jmain=&cw=0"
      puts url
      page = open(url, "Referer" => url)
      content = page.read
      content.force_encoding('UTF-8')
      matches = content.scan(/本次查詢結果共([0-9]*)筆/)
      if matches.length == 0
        puts "{court['name']} {division['name']} has no record"
        continue
      end
      count = matches[0][0].to_i
      matches = content.scan(/FJUDQRY03_1\.aspx\?id=[0-9]*&([^"]*)/)
      if matches.length == 0
        puts "page seems something wrong"
        continue
      end
      params = matches[0][0]
      (1..count).each do |j|
        sleep_random_second()
        case_url = "http://jirs.judicial.gov.tw/FJUD/FJUDQRY03_1.aspx?id=#{j}&#{params}"
        case_page = open(case_url, "Referer" => url)
        case_content = case_page.read
        case_content.force_encoding('UTF-8')
        case_matches = case_content.scan(/href="([^"]*)">友善列印/)
        if case_matches.length == 0
          puts 'cannot find link'
          continue
        end
        print_url = case_matches[0][0];
        queries = CGI.parse(URI.parse(print_url).query)
        puts queries.to_json
        court_code = queries['v_court'][0].split(' ')[0]
        court_name = queries['v_court'][0].split(' ')[1]
        date_string = queries['jrecno'][0].split(',')[3]
        year = queries['jrecno'][0].split(',')[0].to_i
        datetime = DateTime.parse(date_string)
        date_string = datetime.strftime("%Y-%m-%d")
        html = Nokogiri::HTML(case_content)
        judgement_content = html.css('pre')[0].text
        tds = html.css('td')
        reason = tds[10].text
        identify = "#{court_code}-#{queries['jrecno'][0].gsub(',', '-')}"
        if queries['v_sys'][0] == 'V'
          division_name = '民事'
        elsif queries['v_sys'][0] == 'C'
          division_name = '刑事'
        elsif queries['v_sys'][0] == 'A'
          division_name = '行政'
        elsif queries['v_sys'][0] == 'P'
          division_name = '公懲'
        elsif queries['v_sys'][0] == 'I'
          division_name = '少年'
        else
          division_name = '不明'
        end
        sql = "INSERT INTO
                  `judgements`
               SET
                  identify = '#{identify}',
                  court_code = '#{db.escape(court_code)}',
                  court_name = '#{db.escape(court_name)}',
                  year = '#{year}',
                  word = '#{db.escape(queries['jcase'][0])}',
                  number = '#{db.escape(queries['jno'][0])}',
                  division = '#{db.escape(division_name)}',
                  jcheck = '#{db.escape(queries['jcheck'][0])}',
                  reason = '#{db.escape(reason)}',
                  content = '#{db.escape(judgement_content)}',
                  adjudged_at = '#{db.escape(date_string)}',
                  created_at = NOW(),
                  updated_at = NOW()
               ON DUPLICATE KEY UPDATE
                  identify = '#{identify}',
                  court_code = '#{db.escape(court_code)}',
                  court_name = '#{db.escape(court_name)}',
                  year = '#{year}',
                  word = '#{db.escape(queries['jcase'][0])}',
                  number = '#{db.escape(queries['jno'][0])}',
                  division = '#{db.escape(division_name)}',
                  jcheck = '#{db.escape(queries['jcheck'][0])}',
                  reason = '#{db.escape(reason)}',
                  content = '#{db.escape(judgement_content)}',
                  adjudged_at = '#{db.escape(date_string)}',
                  updated_at = NOW()"
        insert = db.query(sql)
      end
    end
  end
end

main()
