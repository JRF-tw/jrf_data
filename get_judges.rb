#!/usr/bin/env ruby

require 'open-uri'
require 'iconv'
require 'nokogiri'
require 'json'
# require 'charlock_holmes'

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


url = 'http://csdi.judicial.gov.tw/abbs/wkw/WHD3A00.jsp'
query_url = 'http://csdi.judicial.gov.tw/abbs/wkw/WHD3A04.jsp?court='

html = get_html(url)

courts = []
courts_section = html.css('option')
courts_section.each do |c|
  court = {}
  court[:name] = c.text
  court[:code] = c.attr('value')
  court[:divisions] = []
  url = query_url + court[:code]
  html = get_html(url)
  tr_section = html.css('tr')
  division = nil
  tr_section.each do |tr|
    if tr.attr('class') == 'title'
      division = {}
      division[:name] = tr.text.strip
      division[:judges] = []
      court[:divisions] << division
    elsif tr.attr('class') == 'tr-1'
      td_section = tr.css('td')
      if td_section[1].text.include? "法官"
        judge = {}
        judge[:branch] = td_section[0].text.strip
        judge[:name] = td_section[1].text.strip.split('　')[0]
        judge[:clerk] = td_section[2].text.strip
        if division[:judges]
          division[:judges] << judge
        end
      end
    end
  end
  courts << court
end

write_json('data/judges.json', courts)