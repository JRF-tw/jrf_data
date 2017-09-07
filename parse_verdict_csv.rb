#!/usr/bin/env ruby

require 'json'
require 'smarter_csv'

verdicts = SmarterCSV.process('./判決書.csv')

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

$result_csv = "court_name,type,reason,count\n"
$result = {}

verdicts.each do |v|
  # puts v
  if ["TPD","SLD","PCD","ILD","KLD","TYD","SCD","MLD","TCD","CHD","NTD","ULD","CYD","TND","KSD","HLD","TTD","PTD","PHD","KMD","LCD"].include?(v[:"法院代號"]) && v[:"宣判年"] == 2016
    unless $result.key? v[:"法院名稱"]
      $result[v[:"法院名稱"]] = {"刑事"=>{}, "民事"=>{}, "行政"=>{}}
    end
    unless $result[v[:"法院名稱"]][v[:"案件類別"]].key? v[:"案由"]
      $result[v[:"法院名稱"]][v[:"案件類別"]][v[:"案由"]] = 1
    else
      $result[v[:"法院名稱"]][v[:"案件類別"]][v[:"案由"]] += 1
    end
  end
end

$result.each_key do |court_name|
  $result[court_name].each_key do |type|
    $result[court_name][type].each_key do |reason|
      $result_csv += "#{court_name},#{type},#{reason},#{$result[court_name][type][reason]}\n"
    end
  end
end
write_json('result.json', $result)
write_file('result.csv', $result_csv)
