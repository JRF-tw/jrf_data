#!/usr/bin/env ruby

require 'json'

def read_data
  data = JSON.parse(File.read('./中華民國刑法.json'))
  return data
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

$data = read_data

$part = nil
$chapter = nil
$section = nil
$sub_section = nil
$result_json = []
$result_csv = "編,章,節,款,條,刑度,內容,註解\n"

$data['law_data'].each do |law_data|
  if law_data.key? 'section_name'
    if law_data['section_name'].match(/第[一二三四五六七八九十]+編/)
      $part = law_data['section_name']
      $chapter = nil
      $section = nil
      $sub_section = nil
    elsif law_data['section_name'].match(/第[一二三四五六七八九十]+章/)
      $chapter = law_data['section_name']
      $section = nil
      $sub_section = nil
    elsif law_data['section_name'].match(/第[一二三四五六七八九十]+節/)
      $section = law_data['section_name']
      $sub_section = nil
    elsif law_data['section_name'].match(/第[一二三四五六七八九十]+款/)
      $sub_section = law_data['section_name']
    end
  elsif law_data.key?('rule_no') && law_data.key?('content')
    if law_data['content'].match(/處.+罰金|處.+有期徒刑/)
      result = {
        result: law_data['content'].scan(/處.+罰金|處.+有期徒刑/)
      }
      result[:part] = $part if $part
      result[:chapter] = $chapter if $chapter
      result[:section] = $section if $section
      result[:sub_section] = $sub_section if $sub_section
      result[:note] = law_data['note']
      result[:content] = law_data['content'].gsub('　', '')
      result[:rule_no] = law_data['rule_no']
      $result_json << result
      result[:result].each do |row|
        $result_csv += "#{$part},#{$chapter},#{$section},#{$sub_section},#{result[:rule_no]},#{row},\"#{result[:content]}\",#{result[:note]}\n"
      end
    end
  end
end

write_json('result.json', $result_json)
write_file('result.csv', $result_csv)