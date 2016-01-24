#!/usr/bin/env ruby

require 'open-uri'
require 'uri'
require 'iconv'
require 'nokogiri'
require 'json'
require 'date'

Dir.chdir(File.dirname(__FILE__))

def write_json(filename, content)
  File.open(filename,"w") do |f|
    f.write(JSON.pretty_generate(content))
  end
end

def get_html(url)
  ic = Iconv.new('UTF-8//IGNORE', 'Big5')
  page = open(url)
  html = Nokogiri::HTML(ic.iconv(page.read))
end

def parse_date(date_string)
  if date_string.length > 0
    begin
      date_string = Date.parse(date_string).strftime('%Y-%m-%d')
    rescue
    end
  end
  return date_string
end

result = []
(1..13500).each do |i|
  url = "http://www.twgiga.com/web/orang/win.asp?ID=#{i}"
  puts url
  html = get_html(url)
  tds = html.css('td')
  if tds.length > 0
    data = {}
    data['姓名'] = tds[10].text().strip
    data['PRID'] = tds[11].text().strip.to_i
    data['性別'] = tds[12].text().strip
    date["出生年月日"] = parse_date(tds[13].text().strip.gsub('/', '-'))
    data['籍貫'] = tds[14].text().strip
    data['教育程度'] = tds[15].text().strip
    data['註'] = tds[16].text().strip.gsub('　', '')
    case_tds = tds.slice(17..-1)
    case_td_group = case_tds.each_slice(19).to_a
    cases = []
    case_td_group.each do |c|
      case_data = {}
      case_data['案號'] = c[4].text().strip
      case_data['年齡'] = c[5].text().strip
      case_data['職業'] = c[6].text().strip
      case_data['國檔局檔號'] = c[7].text().strip
      case_data['案情略述'] = c[9].text().strip.gsub('　', '')
      case_data['確定刑期'] = c[14].text().strip
      case_data['執行刑期'] = c[15].text().strip
      case_data['涉案關係人'] = c[16].text().strip.gsub('　', '')
      case_data['註'] = c[17].text().strip.gsub('　', '')
      cases << case_data
    end
    data['案件'] = cases
    result << data
  end
end
write_json('data/holocausts.json', result)






