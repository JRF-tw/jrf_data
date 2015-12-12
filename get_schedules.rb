#!/usr/bin/env ruby

require 'open-uri'
require 'iconv'
require 'nokogiri'
require 'json'
require 'mechanize'
require 'mysql2'
require 'date'
# require 'charlock_holmes'

def write_json(filename, content)
  File.open(filename,"w") do |f|
    f.write(JSON.pretty_generate(content))
  end
end

def read_db_config
  file = File.read('./db.json')
  return JSON.parse(file)
end

def get_html(url)
  ic = Iconv.new('UTF-8//IGNORE', 'Big5')
  page = open(url)
  html = Nokogiri::HTML(ic.iconv(page.read))
end

def init_db
  db_config = read_db_config()
  return Mysql2::Client.new(:host => db_config['host'], :username => db_config['username'], :password => db_config['password'], :database => db_config['database'])
end

def get_date(date_string, time_string)
  date_list = date_string.split('/')
  date_list[0] = date_list[0].to_i + 1911
  date_string = date_list.join('-')
  time_string = [time_string.slice(0, 2), time_string.slice(2, 4)].join(':')
  datetime_string = [date_string, time_string].join(' ')
  # return Time.parse(datetime_string)
end

def get_options
  ic = Iconv.new('UTF-8//IGNORE', 'Big5')
  uri = URI.parse('http://csdi.judicial.gov.tw/abbs/wkw/WHD3A00.jsp')
  agent = Mechanize.new
  sleep(Random.rand(1..5))
  raw_html = agent.get(uri)
  html = Nokogiri::HTML(ic.iconv(raw_html.body))
  options = html.css('option')
  options = options.map{ |o| o.attribute('value').value }
  return options
end

def get_sys_name(sys)
  # H: 刑事、V: 民事、I: 少年、A: 行政、D: 懲戒及職務
  if sys == 'V'
    return '刑事'
  elsif sys == 'H'
    return '民事'
  elsif sys == 'I'
    return '少年'
  elsif sys == 'A'
    return '行政'
  elsif sys == 'D'
    return '懲戒及職務'
  else
    return '不明'
  end
end

def get_date_section
  today = DateTime.now

  year1 = today.strftime('%Y').to_i - 1911
  date1 = "#{year1}" + today.strftime('%m%d')
  # tomorrow = today + 1
  # year2 = tomorrow.strftime('%Y').to_i - 1911
  # date2 = "#{year2}" + tomorrow.strftime('%m%d')
  return date1, date1
end


def get_page_total(k, v)
  ic = Iconv.new('UTF-8//IGNORE', 'Big5')
  uri = URI.parse('http://csdi.judicial.gov.tw/abbs/wkw/WHD3A02.jsp')
  agent = Mechanize.new
  post_data = {
    'crtid' => k,
    'sys' => v
  }
  header_data = {
    'Origin' => 'http://csdi.judicial.gov.tw',
    'Referer' => 'http://csdi.judicial.gov.tw/abbs/wkw/WHD3A01.jsp'
  }
  sleep(Random.rand(1..5))
  raw_html = agent.post(uri, post_data, header_data)
  html = Nokogiri::HTML(ic.iconv(raw_html.body))

  item_text = html.css('table')[2].css('tr')[0].text.strip
  item_num = item_text.split(' ')[1].to_i
  if item_num == 0
    return 0
  else
    return ( item_num / 15 ) + 1
  end
end

def get_schedules(db, court, division)
  ic = Iconv.new('UTF-8//IGNORE', 'Big5')
  schedules = []
  crtid = court["value"]
  sys = division["value"]
  page_total = get_page_total(crtid, sys)
  date1, date2 = get_date_section()
  if page_total == 0
    return []
  else
    page_total.times.each do |i|
      sql_conction = "UPPER(CRTID)='#{crtid}' AND DUDT>='#{date1}' AND DUDT<='#{date2}' AND SYS='#{sys}'  ORDER BY  DUDT,DUTM,CRMYY,CRMID,CRMNO"
      get_data = {
        'pageNow' => (i + 1),
        'sql_conction' => sql_conction,
        'pageTotal' => page_total,
        'pageSize' => 15,
        'rowStart' => 1
      }
      header_data = {
        'Referer' => 'http://csdi.judicial.gov.tw/abbs/wkw/WHD3A02.jsp'
      }
      uri = URI.parse('http://csdi.judicial.gov.tw/abbs/wkw/WHD3A02.jsp')
      agent = Mechanize.new
      sleep(Random.rand(1..5))
      raw_html = agent.get(uri, get_data)
      html = Nokogiri::HTML(ic.iconv(raw_html.body))
      trs = html.css('table')[1].css('tr')
      trs.length.times.each do |i|
        if i == 0
          next
        end
        tr = trs[i]
        tds = tr.css('td')
        data = {}
        # 類別
        data['division'] = tds[1].text.strip
        # 年度
        data['roc_year'] = tds[2].text.strip.to_i
        # 字別
        data['word'] = tds[3].text.strip
        # 案號
        data['case'] = tds[4].text.strip.gsub(" ", '').to_i
        # 開庭日期
        data['date'] = get_date(tds[5].text.strip, tds[6].text.strip)
        # 法庭
        data['court'] = tds[7].text.strip
        # 股別
        data['section'] = tds[8].text.strip
        # 庭類
        data['process'] = tds[9].text.strip
        puts data.to_json
        schedules << data
        insert = db.query("INSERT INTO schedules (court_name, court_code, division_name, division_code, roc_year, word, number, date, court, section, process, created_at, updated_at)
                       VALUES ('#{db.escape(court['name'])}',
                               '#{db.escape(court['value'])}',
                               '#{db.escape(division['name'])}',
                               '#{db.escape(division['value'])}',
                               '#{data['roc_year']}',
                               '#{db.escape(data['word'])}',
                               '#{data['case']}',
                               '#{db.escape(data['date'])}',
                               '#{db.escape(data['court'])}',
                               '#{db.escape(data['section'])}',
                               '#{db.escape(data['process'])}',
                               NOW(),
                               NOW()
                               )")
      end
    end
    return schedules
  end
end

def get_courts
  ic = Iconv.new('UTF-8//IGNORE', 'Big5')
  date1, date2 = get_date_section()
  db_config = read_db_config()
  db = Mysql2::Client.new(:host => db_config['host'], :username => db_config['username'], :password => db_config['password'], :database => db_config['database'])
  courts = []
  options = get_options()
  options.each do |o|
    uri = URI.parse('http://csdi.judicial.gov.tw/abbs/wkw/WHD3A01.jsp')
    agent = Mechanize.new
    sleep(Random.rand(1..5))
    raw_html = agent.post(uri, {court: o, date1: date1, date2: date2})
    html = Nokogiri::HTML(ic.iconv(raw_html.body))
    radios = html.css('input[type="radio"]')
    radios = radios.map{ |r| r.attribute('value').value }
    child_options = html.css('option')
    child_options.each do |c|
      court = {}
      court["name"] = c.text
      court["value"] = c.attribute('value').value
      court["divisions"] = []
      puts court.to_json
      radios.each do |r|
        division = {}
        division["value"] = r
        division["name"] = get_sys_name(r)
        division["schedules"] = get_schedules(db, court, division)
        court["divisions"] << division
        puts division.to_json
      end
      courts << court
    end
  end
  return courts
end

courts = get_courts()

write_json('data/schedules.json', courts)