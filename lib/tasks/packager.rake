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
  @config ||= OpenStruct.new(YAML.load_file("config/initializers/packager.yml")) # [MY_ENV])
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

    log.info "Collecting parameters"
    params = collect_params(dom)

    log.info "Collecting files"
    process_structure_files(dom)

    collect_bitstreams(dom).each do |bitstream|

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

def collect_params(dom)

  params = Hash.new {|h,k| h[k]=[]}

  config['fields'].each do |field|
    if field.include? "xpath"
      field['xpath'].each do |current_xpath|
        metadata = dom.xpath("#{config['DSpace ITEM']['desc_metadata_prefix']}#{current_xpath}", config['DSpace ITEM']['namespace'])
        if !metadata.empty?
          if field['type'].include? "Array"
            metadata.each do |node|
              params[field[0]] << node.inner_html
            end # metadata.each
          else
            params[field[0]] = metadata.inner_html
          end # "Array"
        end # empty?
      end # xpath.each
    end # field.xpath
  end # typeConfig.each
  return params
end # collect_params

###############################################################################
# If structure files exist, run the package process on each one.
# If bitstream files exist, collect them and attach to the item.
# TODO: Need to resolve above, for License files determine if they are text or PDF
def process_structure_files(dom)
  structData = dom.xpath("#{config['collection_structure']['xpath']}", config['collection_structure']['namespace'])
  structData.each do |fileData|
    unzip_package(fileData.attr('xlink:href'))
  end # structData.each
end

def collect_bitstreams(dom)
  fileList = dom.xpath("#{config['bitstream_structure']['xpath']}", config['bitstream_structure']['namespace'])
  fileArray = []

  fileList.each do |fptr|
    fileChecksum = fptr.at_xpath("premis:objectCharacteristics/premis:fixity/premis:messageDigest", 'premis' => 'http://www.loc.gov/standards/premis').inner_html
    originalFileName = fptr.at_xpath("premis:originalName", 'premis' => 'http://www.loc.gov/standards/premis').inner_html.delete(' ')
    dspaceExportedFile = dom.at_xpath("//mets:file[@CHECKSUM='"+fileChecksum+"']/mets:FLocat", 'mets' => 'http://www.loc.gov/METS/')
    # TODO: Error check files by MD5 Hash

    newFileName = dspaceExportedFile.attr('xlink:href')
    File.rename(@bitstream_dir + "/" + newFileName, @bitstream_dir + "/" + originalFileName)
    fileArray << {'file_type' => dspaceExportedFile.parent.parent.attr('USE'), 'file_name' => File.join(@bitstream_dir,originalFileName)}
  end # fileList.each

  return fileArray
end # collect_files
###############################################################################

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
