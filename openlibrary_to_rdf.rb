require 'rubygems'
require 'json'
require 'zlib'
require 'rdf/threadsafe'
require 'jruby_threach'
require 'redis'
require 'isbn/tools'
require 'openlibrary'

i = 0

include OpenLibrary

if ARGV[0] && ARGV[1]
  DB = Redis.new
  
  if ARGV[2]
    Util.load_lcsh(ARGV[2])
  end
  
  file = Zlib::GzipReader.open(ARGV[0])
  out = Zlib::GzipWriter.open("#{ARGV[1]}/openlibrary-#{DateTime.now.strftime("%Y-%m-%d")}.nt.gz")
  queue = []
  while line = file.gets
    (type,id,rev,date,data) = line.split("\t")
    elements = JSON.parse(data)
    resource = case type
    when "/type/author" then Author.new(elements)
    when "/type/edition" then Edition.new(elements)
    when "/type/work" then Work.new(elements)    
    when "/type/subject" then Subject.new(elements)
    end

    queue << resource if resource
    if queue.length > 1000
      #queue.each do |r|
      queue.threach(3) do |r|
        r.parse_data
      end
      queue.each do |r|
        r.statements.each do |stmt|
          out << stmt.to_ntriples
        end
      end
      queue = []
    end
    i += 1
    if i.to_s =~ /0000$/
      puts i
    end
  end

  out.close
end

