require 'rubygems'
require 'zip'
require 'yaml'
require 'colorize'

namespace :packager do

  desc 'Import DSpace AIP packages into the repository'
  task :aip, [:file] =>  [:environment] do |t, args|
    log.info "Starting rake task ".green + "packager:aip".yellow

    @source_file = args[:file] or raise "No source input file provided."

    ## TODO: Put these options into a config file
    @default_resource_type = 'Thesis'

    log.info "Loading import package from #{@source_file}"

    log.info input_path


    unless File.exists?(File.join(input_path,@source_file))
      log.error "Exiting packager: input file [#{@source_file}] not found."
      abort
    end

    unzip_package(@source_file)

  end
end

def log
  @log ||= Packager::Log.new(config['output_level'])
end

def config
  @config ||= OpenStruct.new(YAML.load_file("config/initializers/packager.yml")) # [MY_ENV])
end

def input_path
  @input_path ||= config['input_dir']
end

def output_path
  @output_path ||= initialize_directory(File.join(input_path, "unpacked"))
end

def complete_path
  @complete_path ||= initialize_directory(File.join(input_path, "complete"))
end

def error_path
  @error_path ||= initialize_directory(File.join(input_path, "error"))
end

def unzip_package(zip_file,parentColl = nil)

  zip_file_path = File.join(input_path, zip_file)

  if File.exist?(zip_file_path)
    file_path = File.join(@output_dir, File.basename(zip_file_path, ".zip"))
    @bitstream_dir = file_path
    Dir.mkdir file_path unless Dir.exist?(file_path)
    Zip::File.open(zip_file_path) do |file_to_extract|
      file_to_extract.each do |compressed_file|
        extract_path = File.join(file_path, compressed_file.name)
        zipfile.extract(compressed_file,extract_path) unless File.exist?(extract_path)
      end
    end
  end
end

def
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
    @mets_XML = Nokogiri::XML(File.open(mets_file))

    current_type = @mets_XML.root.attr("TYPE")
    current_type.slice!("DSpace ")

    log.info "Collecting files"
    process_structure_files

    createItem

    collect_bitstreams.each do |bitstream|

      ## Commented out while refactoring parsing code
      ## file = File.open(bitstream['file_name'])
      ## attached_file = Hyrax::UploadedFile.create(file: file)
      ## attached_file.save
      ## uploadedFiles << attached_file
      ## file.close
      ###########################################################
    end # collect_files.each

    ## Commented out while refactoring parsing code
    ## item = createItem(params)
    ## workFiles = AttachFilesToWorkJob.perform_now(item,uploadedFiles) unless item.nil?
    ## return item
    ####################################################################################
  end
end

def collect_parameters

  parameters = Hash.new {|h,k| h[k]=[]}

  config['fields'].each do |field|
    # puts field
    # if field.include? "xpath"
      field[1]['xpath'].each do |current_xpath|
        # puts "#{current_xpath}"
        metadata = @mets_XML.xpath("#{config['DSpace ITEM']['desc_metadata_prefix']}#{current_xpath}",
                                   config['DSpace ITEM']['namespace'])
        if !metadata.empty?
          if field[1]['type'].include? "Array"
            metadata.each do |node|
              parameters[field[0]] << node.inner_html
            end # metadata.each
          else
            parameters[field[0]] = metadata.inner_html
          end # "Array"
        end # empty?
      end # xpath.each
    # end # field.xpath
  end # typeConfig.each
  puts parameters
  return parameters
end # collect_params

def process_structure_files
  structure_data = @mets_XML.xpath("#{config['collection_structure']['xpath']}",
                                   config['collection_structure']['namespace'])
  structure_data.each do |file_data|
    unzip_package(file_data.attr('xlink:href'))
  end
end

def collect_bitstreams
  fileList = @mets_XML.xpath("#{config['bitstream_structure']['xpath']}", config['bitstream_structure']['namespace'])
  fileArray = []

  fileList.each do |fptr|
    fileChecksum = fptr.at_xpath("premis:objectCharacteristics/premis:fixity/premis:messageDigest",
                                 'premis' => 'http://www.loc.gov/standards/premis').inner_html
    originalFileName = fptr.at_xpath("premis:originalName",
                                     'premis' => 'http://www.loc.gov/standards/premis').inner_html.delete(' ')
    dspaceExportedFile = dom.at_xpath("//mets:file[@CHECKSUM='"+fileChecksum+"']/mets:FLocat",
                                      'mets' => 'http://www.loc.gov/METS/')
    # TODO: Error check files by MD5 Hash

    newFileName = dspaceExportedFile.attr('xlink:href')
    File.rename(@bitstream_dir + "/" + newFileName, @bitstream_dir + "/" + originalFileName)
    fileArray << {'file_type' => dspaceExportedFile.parent.parent.attr('USE'),
                  'file_name' => File.join(@bitstream_dir,originalFileName)}
  end # fileList.each

  return fileArray
end # collect_files

def createItem
  parameters = collect_parameters
  puts parameters
  parameters[:id] = ActiveFedora::Noid::Service.new.mint

  resource_type = @default_resource_type
  unless parameters['resource_type'].first.nil?
    resource_type = parameters['resource_type'].first
  end

  parameters.merge(set_item_visibility(parameters['embargo_release_date']))
  puts parameters
  item = Kernel.const_get(config['type_to_work_map'][resource_type]).new(parameters)
  # item.update(params)
  item.apply_depositor_metadata(depositor.user_key)
  item.save
end

def set_item_visibility(embargo_release_date)
  return { "visibility" => "open" } if embargo_release_date.nil?
  return { "visibility_after_embargo" => "open",
           "visibility_during_embargo" => "authenticated" }
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
