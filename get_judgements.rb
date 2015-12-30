#!/usr/bin/env ruby

require 'open-uri'
require 'uri'
require 'iconv'
require 'nokogiri'
require 'json'
require 'mechanize'
require 'mysql2'
require 'date'
require 'time'
require 'cgi'
require 'elasticsearch'
# require 'charlock_holmes'

Dir.chdir(File.dirname(__FILE__))

def read_config
  file = File.read('./config.json')
  return JSON.parse(file)
end

def init_db
  db_config = read_config()
  if db_config['mysql']['enable']
    mysqldb = Mysql2::Client.new(:host => db_config['mysql']['host'], :username => db_config['mysql']['username'], :password => db_config['mysql']['password'], :database => db_config['mysql']['database'])
  else
    mysqldb = false
  end
  if db_config['elasticsearch']['enable']
    elasticsearchdb = Elasticsearch::Client.new(log: true, host: db_config['elasticsearch']['host'])
  else
    elasticsearchdb = false
  end
  return mysqldb, elasticsearchdb
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

def write_file(filename, content)
  File.open(filename,"w") do |f|
    f.write(content)
  end
end

def sleep_random_second
  now = Time.now
  if (1..5).include?(now.wday) and (8..18).include?(now.hour)
    puts "it is at working hour"
    seconds = Time.new(now.year, now.month, now.day, 19, 1, 0) - now
  else
    seconds = Random.rand(5..20)
  end
  puts "sleep #{seconds} seconds..."
  sleep(seconds)
end

def scan_content(content, pattern)
  begin
    matches = content.scan(pattern)
  rescue
    matches = []
  end
  return matches
end

def get_date_section
  if ARGV[0]
    date1 = Date.parse(ARGV[0]) - 1
    date2 = Date.parse(ARGV[0])
  else
    date1 = Date.today - 8
    date2 = Date.today - 7
  end
  date1 = date1.strftime('%Y%m%d')
  date2 = date2.strftime('%Y%m%d')
  return date2, date2
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

def scan_judges(content)
  content.scan(/法\s+官\s+([\p{Word}\w\s\S]+?)\n/).map { |i| i[0].gsub(' ', '')  }
end

def scan_prosecutors(content)
  content.scan(/檢察官(\p{Word}+)到庭執行職務/).map { |i| i[0] }
end

def scan_lawyers(content)
  content.scan(/\s+(\p{Word}+)律師/).map { |i| i[0] }
end

def scan_clerks(content)
  if content.match(/\n\s+書記官\s+([\p{Word}\w\s\S]+?)\n/)
    content.scan(/\n\s+書記官\s+([\p{Word}\w\s\S]+?)\n/).map { |i| i[0].gsub(' ', '') }
  elsif content.match(/\s+(\p{Word}+)書記官/)
    content.scan(/\s+(\p{Word}+)書記官/).map { |i| i[0] }
  else
    return []
  end
end

def scan_defendants(content)
  if content.match(/\n\s*被\s+告\s+([\p{Word}\w\s\S]+?)\n\s*[\s男\s|\s女\s|上|訴訟|法定|選任|指定|輔\s+佐\s+人]/)
    defendants = content.scan(/\n\s*被\s+告\s+([\p{Word}\w\s\S]+?)\n\s*[\s男\s|\s女\s|上|訴訟|法定|選任|指定|輔\s+佐\s+人]/).map { |i| i[0] }
    defendants = defendants.join("\n")
    defendants = defendants.split(/\n+/).map { |i| i.strip }
    return defendants.uniq
  elsif content.match(/被\s+告\s+(\p{Word}+)/)
    content.scan(/被\s+告\s+(\p{Word}+)/).map { |i| i[0] }
  else
    return []
  end
end

def scan_prosecutor_office(content)
  if content.match(/公\s+訴\s+人\s+(\p{Word}+)/)
    content.scan(/公\s+訴\s+人\s+(\p{Word}+)/).map { |i| i[0] }
  elsif content.match(/聲\s+請\s+人\s+(\p{Word}+)/)
    result = content.scan(/聲\s+請\s+人\s+(\p{Word}+)/).map { |i| i[0] }
    if ["即債權人", "即", "即告訴人", "即具保人"].include?(result[0])
      return []
    else
      return result
    end
  else
    return []
  end
end

def scan_creditors(content)
  content.scan(/\n[即]?債\s*權\s*人\s+(\p{Word}+)/).map { |i| i[0] }
end

def scan_debtors(content)
  if content.match(/債\s+務\s+人\s+(\p{Word}+)/)
    content.scan(/債\s+務\s+人\s+(\p{Word}+)/).map { |i| i[0] }
  elsif content.match(/債務人(\p{Word}+)發支付命令/)
    content.scan(/債務人(\p{Word}+)發支付命令/).map { |i| i[0] }
  else
    return []
  end
end

def scan_judicial_associate_officer(content)
  if content.match(/(\p{Word}+)司法事務官\n/)
    content.scan(/(\p{Word}+)司法事務官\n/).map { |i| i[0] }
  elsif content.match(/司法事務官\s+(\p{Word}+)\s*/)
    content.scan(/司法事務官\s+(\p{Word}+)\s*/).map { |i| i[0] }
  else
    return []
  end
end

def scan_plaintiffs(content)
  if content.match(/原\s+告\s+([\p{Word}\n\S]+)共同訴訟/)
    plaintiffs = content.scan(/原\s+告\s+([\p{Word}\n\s]+)共同訴訟/)[0][0]
    plaintiffs = plaintiffs.split(/[\n]+/).map { |i| i.strip }
    return plaintiffs
  elsif content.match(/原\s+告\s+([\p{Word}\n\S]+)\n被\s+告/)
    plaintiffs = content.scan(/原\s+告\s+([\p{Word}\n\S]+)\n被\s+告/)[0][0]
    plaintiffs = plaintiffs.split(/[\n]+/).map { |i| i.strip }
    return plaintiffs
  elsif content.match(/原\s+告\s+(\p{Word}+)/)
    return content.scan(/原\s+告\s+(\p{Word}+)/).map { |i| i[0] }
  else
    return []
  end
end

def get_characters(content)
  characters = {}
  characters['judges'] = scan_judges(content)
  characters['prosecutors'] = scan_prosecutors(content)
  characters['lawyers'] = scan_lawyers(content)
  characters['clerks'] = scan_clerks(content)
  characters['plaintiffs'] = scan_plaintiffs(content)
  characters['defendants'] = scan_defendants(content)
  characters['prosecutor_office'] = scan_prosecutor_office(content)
  characters['creditors'] = scan_creditors(content)
  characters['debtors'] = scan_debtors(content)
  characters['judicial_associate_officer'] = scan_judicial_associate_officer(content)
  # characters = characters.select { |k,v| v.length > 0 }
  return characters
end

def split_content(content)
  structure = {}
  if content.match(/\s*主\s+文\s*\n([\p{Word}\s\S]+)\s*事\s+實\s*\n/)
    structure['main'] = content.scan(/\s*主\s+文\s*\n([\p{Word}\s\S]+)\s*事\s+實\s*\n/)[0][0].strip
  elsif content.match(/\n\s*主\s+文\s*\n([\p{Word}\s\S]+)\n\s*事\s*實及理\s*由\s*\n/)
    structure['main'] = content.scan(/\n\s*主\s+文\s*\n([\p{Word}\s\S]+)\n\s*事\s*實及理\s*由\s*\n/)[0][0].strip
  elsif content.match(/\n\s*主\s+文\s*\n([\p{Word}\s\S]+)\n\s*犯罪事實\s*及\s*理由.*\n/)
    structure['main'] = content.scan(/\n\s*主\s+文\s*\n([\p{Word}\s\S]+)\n\s*犯罪事實\s*及\s*理由.*\n/)[0][0].strip
  elsif content.match(/\n\s*主\s+文\s*\n([\p{Word}\s\S]+)\n\s*犯罪事實.*\n/)
    structure['main'] = content.scan(/\n\s*主\s+文\s*\n([\p{Word}\s\S]+)\n\s*犯罪事實.*\n/)[0][0].strip
  elsif content.match(/\n\s*主\s+文\s*\n([\p{Word}\s\S]+)\n\s*理\s+由\s*\n/)
    structure['main'] = content.scan(/\n\s*主\s+文\s*\n([\p{Word}\s\S]+)\n\s*理\s+由\s*\n/)[0][0].strip
  end
  if content.match(/\n\s+事\s+實.*\n([\p{Word}\s\S]+)\n\s*理\s+由.*\n/)
    structure['fact'] = content.scan(/\n\s+事\s+實.*\n([\p{Word}\s\S]+)\n\s*理\s+由.*\n/)[0][0].strip
    if content.match(/\n\s*理\s+由.*\n([\p{Word}\s\S]+)\n中\s+華\s+民\s+國\s+/)
      structure['reason'] = content.scan(/\n\s*理\s+由.*\n([\p{Word}\s\S]+)\n中\s+華\s+民\s+國\s+/)[0][0].strip
    end
  elsif content.match(/\n\s*事\s*實及理\s*由.*\n([\p{Word}\s\S]+?)\n中\s+華\s+民\s+國\s+/)
    structure['fact'] = content.scan(/\n\s*事\s*實及理\s*由.*\n([\p{Word}\s\S]+?)\n中\s+華\s+民\s+國\s+/)[0][0].strip
    structure['reason'] = structure['fact']
  elsif content.match(/\n\s+事\s+實.*\n([\p{Word}\s\S]+?)\n中\s+華\s+民\s+國\s+/)
    structure['fact'] = content.scan(/\n\s+事\s+實.*\n([\p{Word}\s\S]+?)\n中\s+華\s+民\s+國\s+/)[0][0].strip
  elsif content.match(/\n\s*犯罪事實\s*及\s*理由.*\n([\p{Word}\s\S]+?)\n中\s+華\s+民\s+國\s+/)
    structure['fact'] = content.scan(/\n\s*犯罪事實\s*及\s*理由.*\n([\p{Word}\s\S]+?)\n中\s+華\s+民\s+國\s+/)[0][0].strip
    structure['reason'] = structure['fact']
  elsif content.match(/\n\s*犯罪事實.*\n([\p{Word}\s\S]+?)\n中\s+華\s+民\s+國\s+/)
    structure['fact'] = content.scan(/\n\s*犯罪事實.*\n([\p{Word}\s\S]+?)\n中\s+華\s+民\s+國\s+/)[0][0].strip
  elsif content.match(/\n\s*理\s+由\s*\n([\p{Word}\s\S]+?)\n中\s+華\s+民\s+國\s+/)
    structure['reason'] = content.scan(/\n\s*理\s+由\s*\n([\p{Word}\s\S]+?)\n中\s+華\s+民\s+國\s+/)[0][0].strip
  end
  structure.select { |k,v| v.length > 0 }
end

def get_division_name(sys)
  if sys == 'V'
    '民事'
  elsif sys == 'C' or sys == 'M'
    '刑事'
  elsif sys == 'A'
    '行政'
  elsif sys == 'P'
    '公懲'
  elsif sys == 'I'
    '少年'
  elsif sys == 'S'
    '訴願'
  else
    '不明'
  end
end

def escape_content(mysqldb, content)
  if content == nil
    nil
  elsif content.kind_of?(Array) or content.kind_of?(Hash)
    mysqldb.escape(content.to_yaml)
  else
    mysqldb.escape(content)
  end
end

def get_page(url, refer, proxy)
  success = false
  until success
    begin
      if proxy
        page = open(url, "Referer" => refer, :proxy => proxy)
      else
        page = open(url, "Referer" => refer)
      end
      content = page.read
      content.force_encoding('UTF-8')
    rescue
      success = false
    end
    success = true
  end
  return content
end

def main
  keyword = URI.escape('年')
  mysqldb, elasticsearchdb = init_db()
  courts = get_courts()
  date1, date2 = get_date_section()
  config = read_config()
  proxy = config["proxy"]["url"]
  courts.each do |court|
    sleep_random_second()
    court_string = URI.escape(court['name']).downcase
    court['divisions'].each do |division|
      url = "http://jirs.judicial.gov.tw/FJUD/FJUDQRY02_1.aspx?&v_court=#{court['code']}+#{court_string}&v_sys=#{division['code']}&jud_year=&jud_case=&jud_no=&jud_no_end=&jud_title=&keyword=&sdate=#{date1}&edate=#{date2}&page=1&searchkw=#{keyword}&jmain=&cw=0"
      puts url
      content = get_page(url, url, proxy)
      matches = scan_content(content, /共\s*([0-9]*)\s*筆\s*\/\s*每頁\s*20\s*筆\s*\//)
      if matches.length == 0
        puts "page seems something wrong"
        write_file('./log/error1.html', content)
        next
      elsif matches[0][0].to_i == 0
        puts "#{court['name']} #{division['name']} has no record"
        next
      end
      count = matches[0][0].to_i
      matches = scan_content(content, /FJUDQRY03_1\.aspx\?id=[0-9]*&([^"]*)/)
      if matches.length == 0
        puts "page seems something wrong"
        write_file('./log/error2.html', content)
        next
      end
      params = matches[0][0]
      (1..count).each do |j|
        sleep_random_second()
        success = false
        until success
          case_url = "http://jirs.judicial.gov.tw/FJUD/FJUDQRY03_1.aspx?id=#{j}&#{params}"
          case_content = get_page(case_url, url, proxy)
          if case_content.length < 350
            puts 'something wrong, retry...'
            sleep_random_second()
          else
            # case_content.force_encoding('UTF-8')
            case_matches = scan_content(case_content, /href="([^"]*)">友善列印/)
            if case_matches.length == 0
              puts 'cannot find link'
            else
              success = true
            end
          end
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
        judgement_content = html.css('pre')[0].text.gsub('　', '  ').gsub("\r", '')
        tds = html.css('td')
        reason = tds[10].text
        identify = "#{court_code}-#{queries['jrecno'][0].gsub(',', '-')}"
        division_name = get_division_name(queries['v_sys'][0])
        structure = split_content(judgement_content)
        characters = get_characters(judgement_content)
        if mysqldb
          sql = "INSERT INTO
                  `judgements`
               SET
                  identify = '#{identify}',
                  court_code = '#{escape_content(mysqldb, court_code)}',
                  court_name = '#{escape_content(mysqldb, court_name)}',
                  division_code = '#{queries['v_sys'][0]}',
                  division_name = '#{escape_content(mysqldb, division_name)}',
                  year = '#{year}',
                  word = '#{escape_content(mysqldb, queries['jcase'][0])}',
                  number = '#{escape_content(mysqldb, queries['jno'][0])}',
                  jcheck = '#{escape_content(mysqldb, queries['jcheck'][0])}',
                  reason = '#{escape_content(mysqldb, reason)}',
                  content = '#{escape_content(mysqldb, judgement_content)}',
                  main = '#{escape_content(mysqldb, structure['main'])}',
                  fact = '#{escape_content(mysqldb, structure['fact'])}',
                  full_reason = '#{escape_content(mysqldb, structure['reason'])}',
                  judges = '#{escape_content(mysqldb, characters['judges'])}',
                  prosecutors = '#{escape_content(mysqldb, characters['prosecutors'])}',
                  lawyers = '#{escape_content(mysqldb, characters['lawyers'])}',
                  clerks = '#{escape_content(mysqldb, characters['clerks'])}',
                  plaintiffs = '#{escape_content(mysqldb, characters['plaintiffs'])}',
                  defendants = '#{escape_content(mysqldb, characters['defendants'])}',
                  prosecutor_office = '#{escape_content(mysqldb, characters['prosecutor_office'])}',
                  creditors = '#{escape_content(mysqldb, characters['creditors'])}',
                  debtors = '#{escape_content(mysqldb, characters['debtors'])}',
                  judicial_associate_officer = '#{escape_content(mysqldb, characters['judicial_associate_officer'])}',
                  adjudged_at = '#{escape_content(mysqldb, date_string)}',
                  created_at = NOW(),
                  updated_at = NOW()
               ON DUPLICATE KEY UPDATE
                  identify = '#{identify}',
                  court_code = '#{escape_content(mysqldb, court_code)}',
                  court_name = '#{escape_content(mysqldb, court_name)}',
                  division_code = '#{queries['v_sys'][0]}',
                  division_name = '#{escape_content(mysqldb, division_name)}',
                  year = '#{year}',
                  word = '#{escape_content(mysqldb, queries['jcase'][0])}',
                  number = '#{escape_content(mysqldb, queries['jno'][0])}',
                  jcheck = '#{escape_content(mysqldb, queries['jcheck'][0])}',
                  reason = '#{escape_content(mysqldb, reason)}',
                  content = '#{escape_content(mysqldb, judgement_content)}',
                  main = '#{escape_content(mysqldb, structure['main'])}',
                  fact = '#{escape_content(mysqldb, structure['fact'])}',
                  full_reason = '#{escape_content(mysqldb, structure['reason'])}',
                  judges = '#{escape_content(mysqldb, characters['judges'])}',
                  prosecutors = '#{escape_content(mysqldb, characters['prosecutors'])}',
                  lawyers = '#{escape_content(mysqldb, characters['lawyers'])}',
                  clerks = '#{escape_content(mysqldb, characters['clerks'])}',
                  plaintiffs = '#{escape_content(mysqldb, characters['plaintiffs'])}',
                  defendants = '#{escape_content(mysqldb, characters['defendants'])}',
                  prosecutor_office = '#{escape_content(mysqldb, characters['prosecutor_office'])}',
                  creditors = '#{escape_content(mysqldb, characters['creditors'])}',
                  debtors = '#{escape_content(mysqldb, characters['debtors'])}',
                  judicial_associate_officer = '#{escape_content(mysqldb, characters['judicial_associate_officer'])}',
                  adjudged_at = '#{escape_content(mysqldb, date_string)}',
                  updated_at = NOW()"
          insert = mysqldb.query(sql)
        end
        if elasticsearchdb
          characters = characters.select { |k,v| v.length > 0 }
          body = {
            court: {
              name: court_name,
              code: court_code
            },
            division: {
              name: division_name,
              code: queries['v_sys'][0]
            },
            year: year,
            word: queries['jcase'][0],
            number: queries['jno'][0],
            jcheck: queries['jcheck'][0],
            reason: reason,
            content: judgement_content,
            structure: structure,
            characters: characters,
            adjudged_at: Date.parse(date_string),
            created_at: DateTime.now,
            updated_at: DateTime.now
          }
          elasticsearchdb.index  index: 'judgements', type: 'judgement', id: identify, body: body
        end
      end
    end
  end
end

main()
