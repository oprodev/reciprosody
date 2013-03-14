class ToolsController < ApplicationController
	before_filter :user_filter, :except => [:index]


	def index
		@tools = Tool.all
	end

	def destroy
		@tool = Tool.find_by_id(params[:id])
		unless @tool
			redirect_to '/perm'
			return
		end
		@tool.destroy
		redirect_to '/tools'
	end

	def show
		@tool = Tool.find_by_id(params[:id])
		redirect_to '/perm' unless @tool
	end

	def new
		@tool = Tool.new
	end

	def edit
		@tool = Tool.find_by_id(params[:id])
		redirect_to '/perm' unless @tool
	end

	def update
		@tool = Tool.find_by_id(params[:id])
		redirect_to '/perm' unless @tool

		owner_text = params[:tool].delete(:owner)
		corpora_text = params[:tool].delete(:corpora)

		if !owner_text || owner_text.blank?
			@tool.errors[:owner] = " must be specified"
		end

		owner_email = ""
		if owner_text =~ /\<(.+)\>/
			owner_email = $1
		end
		@owner = User.find_by_email(owner_email);
		if !@owner
			@tool.errors[:owner] = " does not exist."  	
		end

		@corpora = corpora_from_text(corpora_text)

		respond_to do |format|
			if @tool.errors.none? && @tool.update_attributes(params[:tool]) && create_tool
				ToolMembership.where(:user_id => current_user()).destroy_all

				ToolMembership.create(
					:tool_id	=> @tool.id, 
					:user_id		=> current_user().id,
					:role			=> 'owner')

				format.html {redirect_to @tool}
				format.json do
					render :json => {:ok => true, :res => @tool.id}
				end
			else
				format.json do 
					render :json => {:ok => false, :res => "#{@tool.errors.full_messages}"}
				end
			end
		end

	end

	# POST /tools
	def create
		owner_text = params[:tool].delete(:owner)
		corpora_text = params[:tool].delete(:corpora)

		@tool = Tool.new(params[:tool])

		if !owner_text || owner_text.blank?
			@tool.errors[:owner] = " must be specified"
		end

		owner_email = ""
		if owner_text =~ /\<(.+)\>/
			owner_email = $1
		end
		@owner = User.find_by_email(owner_email);
		if !@owner
			@tool.errors[:owner] = " does not exist."  	
		end

		@corpora = corpora_from_text(corpora_text)

		respond_to do |format|
			if @tool.errors.none? && @tool.save && create_tool

				ToolMembership.create(
					:tool_id	=> @tool.id, 
					:user_id		=> current_user().id,
					:role			=> 'owner')

				format.html {redirect_to @tool}
				format.json do
					render :json => {:ok => true, :res => @tool.id}
				end
			else
				format.json do 
					render :json => {:ok => false, :res => "#{@tool.errors.full_messages}"}
				end
			end
		end
	end

	private

	def create_tool
		return true
	end

	def corpora_from_text(corpora_text)
		corpora = []
		if corpora_text && !corpora_text.blank?
			corpora_text.split("\n").each do |cid|
				corp = Corpus.find_by_id(cid)
				corpora << corp if corp
			end
		end
		return corpora
	end
	#--------FILTERS--------------------------------------------------------
  	# 
  	#-----------------------------------------------------------------------

  	# Allows only users
	def user_filter
		redirect_to '/perm' unless user_signed_in?
	end
end