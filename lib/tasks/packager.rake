require 'rubygems'
require 'zip'
require 'yaml'
require 'colorize'

@type_to_work_map = {
  "Thesis" => "Thesis",
  "Dissertation" => "Dissertation",
  "Project" => "Project",
  "Newspaper" => "Newspaper",
  "Article" => "Publication",
  "Poster" => "Publication",
  "Report" => "Publication",
  "Preprint" => "Publication",
  "Technical Report" => "Publication",
  "Working Paper" => "Publication",
  "painting" => "CreativeWork",
  "ephemera" => "CreativeWork",
  "textiles" => "CreativeWork",
  "Empirical Research" => "CreativeWork",
  "Award Materials" => "CreativeWork",
  "photograph" => "CreativeWork",
  "Mixed Media" => "CreativeWork",
  "Other" =>  "CreativeWork",
  "Creative Works" => "CreativeWork"
}

@attributes = {
  "dc.contributor" => "contributor",
  "dc.contributor.advisor" => "advisor",
  "dc.contributor.author" => "creator",
  "dc.creator" => "creator",
  "dc.date" => "date_created",
  "dc.date.created" => "date_created",
  "dc.date.issued" => "date_issued",
  "dc.date.submitted" => "date_submitted",
  "dc.identifier" => "identifier",
  "dc.identifier.citation" => "bibliographic_citation",
  "dc.identifier.isbn" => "identifier",
  "dc.identifier.issn" => "identifier",
  "dc.identifier.other" => "identifier",
  "dc.identifier.uri" => "handle",
  "dc.description" => "description",
  "dc.description.abstract" => "abstract",
  "dc.description.provenance" => "provenance",
  "dc.description.sponsorship" => "sponsor",
  "dc.format.extent" => "extent",
  # "dc.format.medium" => "",
  "dc.language" => "language",
  "dc.language.iso" => "language",
  "dc.publisher" => "publisher",
  "dc.relation.ispartofseries" => "is_part_of",
  "dc.relation.uri" => "related_url",
  "dc.rights" => "rights_statement",
  "dc.subject" => "subject",
  "dc.subject.lcc" => "identifier",
  "dc.subject.lcsh" => "keyword",
  "dc.title" => "title",
  "dc.title.alternative" => "alternative_title",
  "dc.type" => "resource_type",
  "dc.type.genre" => "resource_type",
  "dc.contributor.sponsor" => "sponsor",
  "dc.advisor" => "advisor",
  "dc.genre" => "resource_type",
  "dc.contributor.committeemember" => "committee_member",
  # dc.note" => "",
  "dc.rights.license" => "license",
  "dc.rights.usage" => "rights_statement",
  "dc.sponsor" => "sponsor"
}

@singulars = {
  "dc.date.available" => "date_uploaded", # Newspaper
  "dc.date.accessioned" => "date_accessioned", # Thesis
  "dc.date.embargountil" => "embargo_release_date", # Thesis
  "dc.date.updated" => "date_modified",
  "dc.description.embargoterms" => "embargo_terms",
}

namespace :packager do

  task :aip, [:file, :user_id] =>  [:environment] do |t, args|
    puts "Starting rake task ".green + "packager:aip".yellow

    @coverage = "" # for holding the current DSpace COMMUNITY name
    @sponsorship = "" # for holding the current DSpace CoLLECTIOn name

    @source_file = args[:file] or raise "No source input file provided."

    ## TODO: Put these options into a config file
    @defaultDepositor = User.find_by_user_key(args[:user_id]) # THIS MAY BE UNNECESSARY
    @default_type = 'Thesis'

    puts "Loading import package from #{@source_file}"

    abort("Exiting packager: input file [#{@source_file}] not found.".red) unless File.exists?(@source_file)

    @input_dir = File.dirname(@source_file)
    @output_dir = initialize_directory(File.join(@input_dir, "unpacked")) ## File.basename(@source_file,".zip"))
    @complete_dir = initalize_directory(File.join(@input_dir, "complete")) ## File.basename(@source_file,".zip"))
    @error_dir = initialize_directory(File.join(@input_dir, "error")_ ## File.basename(@source_file,".zip"))

    unzip_package(File.basename(@source_file))

  end
end

def unzip_package(zip_file,parentColl = nil)

  zpath = File.join(@input_dir, zip_file)

  if File.exist?(zpath)
    file_dir = File.join(@output_dir, File.basename(zpath, ".zip"))
    @bitstream_dir = file_dir
    Dir.mkdir file_dir unless Dir.exist?(file_dir)
    Zip::File.open(zpath) do |zipfile|
      zipfile.each do |f|
        fpath = File.join(file_dir, f.name)
        zipfile.extract(f,fpath) unless File.exist?(fpath)
      end
    end
    if File.exist?(File.join(file_dir, "mets.xml"))
      begin
        processed_mets = process_mets(File.join(file_dir,"mets.xml"),parentColl)
        File.rename(zpath,File.join(@complete_dir,zip_file))
      rescue StandardError => e
        puts e
        File.rename(zpath,File.join(@error_dir,zip_file))
      end
      return processed_mets
    else
      puts "No METS data found in package."
    end
  end

end

def process_mets (mets_file,parentColl = nil)

  children = Array.new
  files = Array.new
  uploadedFiles = Array.new
  depositor = ""
  type = ""
  params = Hash.new {|h,k| h[k]=[]}

  if File.exist?(mets_file)
    dom = Nokogiri::XML(File.open(mets_file))

    current_type = dom.root.attr("TYPE")
    current_type.slice!("DSpace ")

    data = dom.xpath("//dim:dim[@dspaceType='"+current_type+"']/dim:field", 'dim' => 'http://www.dspace.org/xmlns/dspace/dim')

    data.each do |element|
     field = element.attr('mdschema') + "." + element.attr('element')
     field = field + "." + element.attr('qualifier') unless element.attr('qualifier').nil?

     # Due to duplication and ambiguity of output fields from DSpace
     # we need to do some very simplistic field validation and remapping
     case field
     when "dc.creator"
       if element.inner_html.match(/@/)
         depositor = getUser(element.inner_html) unless @debugging
       end
     else
       # params[@attributes[field]] << element.inner_html.gsub "\r", "\n" if @attributes.has_key? field
       # params[@singulars[field]] = element.inner_html.gsub "\r", "\n" if @singulars.has_key? field
       params[@attributes[field]] << element.inner_html if @attributes.has_key? field
       params[@singulars[field]] = element.inner_html if @singulars.has_key? field
     end
    end

    case dom.root.attr("TYPE")
    when "DSpace COMMUNITY"
      type = "admin_set"
      puts params
      @coverage = params["title"][0]
      puts "*** COMMUNITY ["+@coverage+"] ***"
    when "DSpace COLLECTION"
      type = "admin_set"
      @sponsorship = params["title"][0]
      puts "***** COLLECTION ["+@sponsorship+"] *****"
    when "DSpace ITEM"
      puts "******* ITEM ["+params["handle"][0]+"] *******"
      type = "work"
      # params["sponsorship"] << @sponsorship
      # params["coverage"] << @coverage
    end

    if type == 'admin_set'
      structData = dom.xpath('//mets:mptr', 'mets' => 'http://www.loc.gov/METS/')
      structData.each do |fileData|
        case fileData.attr('LOCTYPE')
        when "URL"
          unzip_package(fileData.attr('xlink:href'))
        end
      end
    elsif type == 'work'

      fileMd5List = dom.xpath("//premis:object", 'premis' => 'http://www.loc.gov/standards/premis')
      fileMd5List.each do |fptr|
        fileChecksum = fptr.at_xpath("premis:objectCharacteristics/premis:fixity/premis:messageDigest", 'premis' => 'http://www.loc.gov/standards/premis').inner_html
        originalFileName = fptr.at_xpath("premis:originalName", 'premis' => 'http://www.loc.gov/standards/premis').inner_html

        ########################################################################################################################
        # This block seems incredibly messy and should be cleaned up or moved into some kind of method
        #
        newFile = dom.at_xpath("//mets:file[@CHECKSUM='"+fileChecksum+"']/mets:FLocat", 'mets' => 'http://www.loc.gov/METS/')
        thumbnailId = nil
        case newFile.parent.parent.attr('USE') # grabbing parent.parent seems off, but it works.
        when "THUMBNAIL"
          newFileName = newFile.attr('xlink:href')
          puts newFileName + " -> " + originalFileName
          File.rename(@bitstream_dir + "/" + newFileName, @bitstream_dir + "/" + originalFileName)
          file = File.open(@bitstream_dir + "/" + originalFileName)

          sufiaFile = Hyrax::UploadedFile.create(file: file)
          sufiaFile.save

          uploadedFiles.push(sufiaFile)
          file.close
        when "TEXT"
        when "ORIGINAL"
          newFileName = newFile.attr('xlink:href')
          puts newFileName + " -> " + originalFileName
          File.rename(@bitstream_dir + "/" + newFileName, @bitstream_dir + "/" + originalFileName)
          file = File.open(@bitstream_dir + "/" + originalFileName)
          sufiaFile = Hyrax::UploadedFile.create(file: file)
          sufiaFile.save
          uploadedFiles.push(sufiaFile)
          file.close
        when "LICENSE"
          # Temp commented to deal with PDFs
          # newFileName = newFile.attr('xlink:href')
          # puts "license text: " + @bitstream_dir + "/" + newFileName
          # file = File.open(@bitstream_dir + "/" + newFileName, "rb")
          # params["rights_statement"] << file.read
          # file.close
        end
        ###
        ########################################################################################################################

      end

      puts "-------- UpLoaded Files ----------"
      puts uploadedFiles
      puts "----------------------------------"

      puts "** Creating Item..."
      item = createItem(params,depositor) unless @debugging
      puts "** Attaching Files..."
      workFiles = AttachFilesToWorkJob.perform_now(item,uploadedFiles) unless @debugging
      return item
    end
  end
end

def createCollection (params, parent = nil)
  coll = AdminSet.new(params)
#  coll = Collection.new(id: ActiveFedora::Noid::Service.new.mint)
#  params["visibility"] = "open"
#  coll.update(params)
#  coll.apply_depositor_metadata(@current_user.user_key)
  coll.save
#  return coll
end


def createItem (params, depositor, parent = nil)
  if depositor == ''
    depositor = @defaultDepositor
  end


  puts "Part of: #{params['part_of']}"

  id = ActiveFedora::Noid::Service.new.mint

  # Not liking this case statement but will refactor later.
  rType = @default_type
  rType = params['resource_type'].first unless params['resource_type'].first.nil?

  puts "Type: #{rType} - #{@type_to_work_map[rType]}"
  item = Kernel.const_get(@type_to_work_map[rType]).new(id: id)

  # item = Thesis.new(id: ActiveFedora::Noid::Service.new.mint)
  # item = Newspaper.new(id: ActiveFedora::Noid::Service.new.mint)

  if params.key?("embargo_release_date")
    # params["visibility"] = "embargo"
    params["visibility_after_embargo"] = "open"
    params["visibility_during_embargo"] = "authenticated"
  else
    params["visibility"] = "open"
  end

  # add item to default admin set
  # params["admin_set_id"] = AdminSet::DEFAULT_ID

  item.update(params)
  item.apply_depositor_metadata(depositor.user_key)
  item.save
  return item
end

def getUser(email)
  user = User.find_by_user_key(email)
  if user.nil?
    pw = (0...8).map { (65 + rand(52)).chr }.join
    puts "Created user " + email + " with password " + pw
    user = User.new(email: email, password: pw)
    user.save
  end
  # puts "returning user: " + user.email
  return user
end

def initialize_directory(dir)
  Dir.mkdir dir unless Dir.exist?(dir)
  return dir
end

# Method for printing to the shell without puts newline. Good for showing
# a shell progress bar, etc...
def print_and_flush(str)
  print str
  $stdout.flush
end
