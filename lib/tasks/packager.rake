require 'rubygems'
require 'zip'
require 'yaml'
require 'colorize'

namespace :packager do

  task :aip, [:file] =>  [:environment] do |t, args|
    log.info "Starting rake task ".green + "packager:aip".yellow

    @source_file = args[:file] or raise "No source input file provided."

    ## TODO: Put these options into a config file
    @defaultDepositor = User.find_by_user_key(config['depositor']) # THIS MAY BE UNNECESSARY
    @default_type = 'Thesis'

    log.info "Loading import package from #{@source_file}"


    @input_dir = config['input_dir']
    log.info @input_dir


    unless File.exists?(File.join(@input_dir,@source_file))
      log.error "Exiting packager: input file [#{@source_file}] not found."
      abort
    end

    @output_dir = initialize_directory(File.join(@input_dir, "unpacked")) ## File.basename(@source_file,".zip"))
    @complete_dir = initialize_directory(File.join(@input_dir, "complete")) ## File.basename(@source_file,".zip"))
    @error_dir = initialize_directory(File.join(@input_dir, "error")) ## File.basename(@source_file,".zip"))

    unzip_package(File.basename(@source_file))

  end
end

def log
  @log ||= Packager::Log.new(config['output_level'])
end

def config
  @config ||= OpenStruct.new(YAML.load_file("config/packager.yml")) # [MY_ENV])
end

def type_config
  # @typeConfig ||= Array.new
  @typeConfig = OpenStruct.new(YAML.load_file("config/packager/" + @type + ".yml"))
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
        log.error e
        File.rename(zpath,File.join(@error_dir,zip_file))
        abort if config['exit_on_error']
      end
      return processed_mets
    else
      log.warn "No METS data found in package."
    end
  end

end

def process_mets (mets_file,parentColl = nil)

  children = Array.new
  files = Array.new
  uploadedFiles = Array.new
  depositor = ""
  type = ""
  # params = Hash.new {|h,k| h[k]=[]}

  if File.exist?(mets_file)
    dom = Nokogiri::XML(File.open(mets_file))

    current_type = dom.root.attr("TYPE")
    current_type.slice!("DSpace ")

    params = collect_params(dom)

    case dom.root.attr("TYPE")
    when "DSpace COMMUNITY"
      type = "admin_set"
      # @coverage = params["title"][0]
      # puts "*** COMMUNITY ["+@coverage+"] ***"
    when "DSpace COLLECTION"
      type = "admin_set"
      # @sponsorship = params["title"][0]
      # puts "***** COLLECTION ["+@sponsorship+"] *****"
    when "DSpace ITEM"
      log.info "ingesting item: #{params['handle'][0]}"
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
          if config['include_thumbnail']
            newFileName = newFile.attr('xlink:href')
            log.info "renaming thumbnail bitstream #{newFileName} -> #{originalFileName}"
            File.rename(@bitstream_dir + "/" + newFileName, @bitstream_dir + "/" + originalFileName)
            file = File.open(@bitstream_dir + "/" + originalFileName)

            sufiaFile = Hyrax::UploadedFile.create(file: file)
            sufiaFile.save

            uploadedFiles.push(sufiaFile)
            file.close
          end
        when "TEXT"
        when "ORIGINAL"
          newFileName = newFile.attr('xlink:href')
          log.info "renaming original bitstream #{newFileName} -> #{originalFileName}"
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

      log.info "Creating Hyrax Item..."
      item = createItem(params,depositor) unless @debugging
      log.info "Attaching Uploaded Files..."
      workFiles = AttachFilesToWorkJob.perform_now(item,uploadedFiles) unless @debugging
      return item
    end
  end
end

def collect_params(dom)

  params = Hash.new {|h,k| h[k]=[]}

  config['fields'].each do |field|
    field = field[1]
    if field.include? "xpath"
      field['xpath'].each do |current_xpath|
        metadata = dom.xpath("#{config['DSpace ITEM']['desc_metadata_prefix']}#{current_xpath}", config['DSpace ITEM']['namespace'])
        if !metadata.empty?
          if field['type'].include? "Array"
            metadata.each do |node|
              params[field['property']] << node.inner_html
            end # metadata.each
          else
            params[field['property']] = metadata.inner_html
          end # "Array"
        end # empty?
      end # xpath.each
    end # field.xpath
  end # typeConfig.each
  return params
end # collect_params

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

  id = ActiveFedora::Noid::Service.new.mint

  # Not liking this case statement but will refactor later.
  rType = @default_type
  rType = params['resource_type'].first unless params['resource_type'].first.nil?

  item = Kernel.const_get(config['type_to_work_map'][rType]).new(id: id)

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
    log.info "Generated account for #{email}"
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
