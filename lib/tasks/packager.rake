require 'rubygems'
require 'zip'
require 'yaml'
require 'colorize'

namespace :packager do

  desc 'Import DSpace AIP packages into the repository'
  task :aip, [:file] =>  [:environment] do |t, args|
    log.info "Starting rake task ".green + "packager:aip".yellow

    params = { :source_file => args[:file],
               :source_path => File.join(input_path,args[:file]),
               :default_resource_type => "Thesis"
             } or raise "No source input file provided."

    log.info "Loading import package from #{params[:source_file]}"

    log.info params[:source_file]

    unless File.exists?(params[:source_path])
      log.error "Exiting packager: input file [#{params[:source_file]}] not found."
      abort
    end

    unzip_package(params)

  end
end

def log
  @log ||= Packager::Log.new(config['output_level'])
end

def config
  @config ||= Rails.application.config_for(:packager)
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

def unzip_package(params)

  params[:unpacked_path] = initialize_directory(File.join(output_path, File.basename(params[:source_file], ".zip")))
  params[:files] = Array.new

  Zip::File.open(params[:source_path]) do |file_to_extract|
    file_to_extract.each do |compressed_file|
      puts File.join(params[:unpacked_path], compressed_file.name)
      params[:files] << {:source_path => File.join(params[:unpacked_path], compressed_file.name)}
      unpack_file(file_to_extract,File.join(params[:unpacked_path], compressed_file.name))
    end
  end

  puts params
end

def unpack_file(compressed_file,file_to_unpack)
  compressed_file.extract(File.basename(file_to_unpack),file_to_unpack) unless File.exist?(file_to_unpack)
  return file_to_unpack
end

def get_mets_data
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
