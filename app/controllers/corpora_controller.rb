class CorporaController < ApplicationController
	before_filter :auth, :except => :index
	#before_filter :block, :only => [:edit, :update]
	
	autocomplete :language, :name
	autocomplete :license, :name
	
  # GET /corpora
  # GET /corpora.json
  def index
    @corpora = Corpus.all
		
    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @corpora }
    end
  end

  # GET /corpora/1
  # GET /corpora/1.json
  def show
    @corpus = Corpus.find(params[:id])
		@archives = []
		@archive_names = Dir.entries("corpora.archives/#{@corpus.utoken}").select {|n| n != ".." && n != "." }
		
		#--Sort from highest to lowest Version
		@archive_names.sort! do |a, b|
			logger.info("a=#{a} b=#{b}")
			x = a.gsub(/\.#{get_archive_ext(a)}$/, '')[/\d+$/].to_i
			y = b.gsub(/\.#{get_archive_ext(b)}$/, '')[/\d+$/].to_i
			y <=> x
		end
		
		@archive_names.each do |n|
			@archives.push ["V."+n[/\d+\.(zip|tgz|tar\.gz|)$/], n]
		end
		
		
    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @corpus }
    end
  end

  # GET /corpora/new
  # GET /corpora/new.json
  def new
    @corpus = Corpus.new
	
    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @corpus }
    end
  end

  # GET /corpora/1/edit
  def edit
    @corpus = Corpus.find(params[:id])
  end
  
  # GET /corpora/1/download
  def download
  	@corpus = Corpus.find(params[:id])
  	@filename = params[:name]
  	
  	#To-Do: Error/Evil checking

  	archive_path = "corpora.archives/#{@corpus.utoken}/#{@filename}"
  	
  	if invalid_filename?(@filename) && !File.file?(archive_path)
  		redirect_to '/perm'
  	else
  		send_file archive_path
  	end
  end
	
  # POST /corpora
  def create
    @corpus = Corpus.new(params[:corpus])
		@file = @corpus.upload_file
		
		logger.info "FILE = #{@file}"
		

		@corpus.valid? #note to self, overwrites existing errors
		if !@file
  		@corpus.errors[:upload_file] = " is missing"
		end
		
	  respond_to do |format|
	    if @corpus.errors.none? && create_corpus() && @corpus.save
	      format.html { redirect_to @corpus, notice: 'Corpus was successfully created.' }
	    else
	      format.html { render action: "new" }
	    end
	  end
	
  end
 
  # POST /corpora/1 <-This is currently used for edit
  def post_update
    @corpus = Corpus.find(params[:id])
    
		@corpus.upload = params[:corpus][:upload]
		
		@file = @corpus.upload_file
		logger.info "---------------FILE = #{@file}"

		@corpus.valid? #note to self, overwrites existing errors
		if !@file
			logger.info "----NO FILE----!!!!----"
  		@corpus.errors[:upload_file] = " is missing"
  	else
  		create_corpus()
		end
		
    respond_to do |format|
    	if @corpus.update_attributes(params[:corpus]) && @corpus.save
        format.html { redirect_to @corpus, notice: 'Corpus was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: "edit" }
        format.json { render json: @corpus.errors, status: :unprocessable_entity }
      end
    end
  end
  
  # PUT /corpora/1
  def update
    @corpus = Corpus.find(params[:id])

		@file = @corpus.upload_file
		
		logger.info "FILE = #{@file}"
		

		@corpus.valid? #note to self, overwrites existing errors
		if !@file
  		@corpus.errors[:upload_file] = " is missing"
  	else
  		create_corpus()
		end
		
    respond_to do |format|
    	if @corpus.update_attributes(params[:corpus]) && @corpus.save
        format.html { redirect_to @corpus, notice: 'Corpus was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: "edit" }
        format.json { render json: @corpus.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /corpora/1
  # DELETE /corpora/1.json
  def destroy
    @corpus = Corpus.find(params[:id])
    @corpus.destroy

    respond_to do |format|
      format.html { redirect_to corpora_url }
      format.json { head :no_content }
    end
  end
  
  private
  
  def create_corpus
  	archive_ext = get_archive_ext(@file.original_filename);
  	if !archive_ext
  		@corpus.errors[:file_type] = "must be zip or tar.gz or tgz"
  		return false
  	end
  	
  	#prepare xtract directory
  	@corpus.utoken = gen_unique_token() if !@corpus.utoken
  	
  	logger.info "----utoken = #{@corpus.utoken}"
  	
  	xtract_dir = "corpora.files/#{@corpus.utoken}"
  	if Dir.exists? xtract_dir
  		#--clear the directory--(for now)
  		`rm -rf #{xtract_dir}/*`
  	else
  		Dir.mkdir xtract_dir
  	end
  	#Dir.mkdir xtract_dir unless Dir.exists? xtract_dir
  	
  	#prepare archive directory
  	archive_dir = "corpora.archives/#{@corpus.utoken}"
  	Dir.mkdir archive_dir unless Dir.exists? archive_dir
  	
  	#archive_name = @file.original_filename[0..-(archive_ext.length+2)]
  	
  	#Note: Using original filename + version doesn't work because
  	# archive_name.zip --upload-> archive_name.0.zip --upload-> archive_name.0.1.zip --upload-> archive_name.0.1.2.zip
  	# so it requires also stripping the original version number from the filename if it contains one
  	# so it a bit messy for now. To-Do: I must fix this
  	
  	#For now: Use de-humanized version of corpus.name
  	archive_name = @corpus.name.downcase.gsub(/\s+/, '_');
  	archive_path = "#{archive_dir}/#{archive_name}.#{file_count(archive_dir)}.#{archive_ext}"
  	logger.info "-----------------PATH = #{archive_path}"
  	logger.info "-----------------FILETYPE = #{@file.class}"
  	File.open(archive_path, "wb") {|f| f.write(@file.read)}
    
  	begin
			#---now extract the archive based on ext--
			if archive_ext == "tar.gz" || archive_ext == "tgz"
				untar(archive_path, xtract_dir)
			elsif archive_ext == "zip"
				unzip(archive_path, xtract_dir)
			end
		rescue => exception
			#---something went wrong, so delete directories---
			#FileUtils.rm_rf("corpora.files/#{@corpus.utoken}/");
  		#FileUtils.rm_rf("corpora.archives/#{@corpus.utoken}/");
  		@corpus.remove_dirs
  		@corpus.errors[:internal] = " issue extracting your archive"
  		return false
		end
  	
  	return true
  end
  
  def unzip(zip_path, xtract_dir)
  	files = `unzip -l #{zip_path}`.split("\n")
  	files.shift(3); files.pop(2);
  	files.map! {|f| f[30..-1]}
    
  	`unzip #{zip_path} -d #{xtract_dir}`
    container = container(files)
    if container
        `mv #{xtract_dir}/#{container} #{xtract_dir}/#{@corpus.utoken}` #Safety - in case container contains folder with same name as container
        `mv #{xtract_dir}/#{@corpus.utoken}/** #{xtract_dir}`
        `rm -rf #{xtract_dir}/#{@corpus.utoken}`
    end
 
  end
  
  def untar(tarpath, xtract_dir)
  	strip = "--strip 1";
  	files = `tar tf #{tarpath}`.split("\n")
    strip = "" if container(files) == nil
  	#-------------------------------------------
  	logger.info "tar zxf #{tarpath} -C #{xtract_dir} #{strip}"
  	system("tar zxf #{tarpath} -C #{xtract_dir} #{strip}");
  end
  
  
  
  # returns the name of the container if there is one
  # returns nil otherwise (when there is no container)
  def container(files)
  	container = files[0][/^[^\/]+\//]
  	files.each do |f|
  		if(f[/^[^\/]+\//] != container)
  			return nil
  		end
  	end
  	return container
  end
  
  def gen_unique_token()
  	utoken = ""
  	begin
  		utoken = SecureRandom.uuid
  	end while Corpus.where(:utoken => utoken).exists?
  	return utoken
  end
  
  def get_archive_ext(string)
  	return "tar.gz" if string =~ /\.tar\.gz$/
  	return "tgz" 		if string =~ /\.tgz$/
  	return "zip"		if string =~ /\.zip$/
  	return nil
  end
  
  def file_count(dir)
  	return Dir.glob("#{dir}/*").length
  end
  
  def invalid_filename?(name)
  	return true if name =~ /^\.\./
  	return true if name =~ /\~/
  	return false
  end
  
  def auth
  	if !user_signed_in?
  		redirect_to '/perm'
  	end
  end
  
  def block
  	redirect_to '/perm'
  end
end