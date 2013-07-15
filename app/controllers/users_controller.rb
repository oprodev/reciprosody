class UsersController < ApplicationController
	protect_from_forgery
	before_filter :auth

	
	#GET /users/mixed_search
	#params[:q] = query
	def mixed_search
		q = params[:q]
		unless q && q.length > 2
			render :json => []
			return
		end

		q = "%#{q}%"
		render :json => User.where("name LIKE ? OR email LIKE ?", q, q)
	end

	# GET /user/inbox_delete
	# params[:mids] = message ids (newline separated)
	def inbox_delete
		@user = current_user()
		mids = params[:mids]
		unless mids
			render :json => {:ok => false}
			return
		end
		mids_hash = Hash.new

		mids = mids.split("\n").map {|e| e.to_i}
		mids.each do |id| mids_hash[id] = true end

		permanently_deleted = 0
		@user.deleted_messages.process do |message|
			if mids_hash[message.id]
				message.delete
				permanently_deleted += 1
			end
		end

		moved_to_trash = 0
		@user.received_messages.process do |message|
			
		end

		render :json => {:ok => true, :mids => mids, :permanently_deleted => permanently_deleted}
	end

	# GET /users/inbox
	def inbox
		view = params[:v]
		mid = params[:mid]

		@user = current_user
		@received = @user.received_messages
		@readed = @user.received_messages.readed
		@unreaded = @user.received_messages.unreaded
		@deleted = @user.deleted_messages.are_to(@user)
		@sent = @user.sent_messages

		@select_messages = nil
		case view
		when "received"
			@select_messages = @received
			@view = :received #inbox
		when "read"
			@select_messages = @readed
			@view = :read
		when "unread"
			@select_messages = @unreaded
			@view = :unread
		when "sent"
			@select_messages = @sent
			@view = :sent
		when "trash"
			@select_messages = @deleted
			@view = :trash
		else
			@select_messages = @received
			@view = :received
		end

		if mid && !mid.blank?
			@message = @select_messages.with_id(mid).all
		else
			@message = nil
		end

		@message = @message[0] if @message && @message.length > 0
	end

	# GET /users/:id
	def show # show current user home page
		logger.info "**USER SHOW**"
		@user = nil
		q = params[:id]

		if q
			if q.include?("@")
				@user = User.find_by_email(q)
			else
				@user = User.find_by_id(q)
			end
		end

		if @user && current_user() != @user
			render :public_profile
			return
		end

		render :show
	end
	
	# GET /user/
	def index
		@users = User.all
	end
	
	# GET /user/invite
	def invite
		
	end
	
	# POST /users/invite_user
	def invite_user
		name	= params[:name]
		email = params[:email]
		
		respond_to do |format|
			if name != nil && !name.blank? && email != nil && !email.blank? && email_valid(email) && User.find_by_email(email) == nil
				logger.info("****Name  = #{name}")
				logger.info("****Email = #{email}")
				#--Create and Save User--
				@tmp_password = Devise.friendly_token[0,6]
				@new_user = User.new(:name => name.titleize, :email => email, :password => @tmp_password, :password_confirmation => @tmp_password)
				logger.info("**NEW USER**\n")
				logger.info(@new_user.to_s)
				
				@new_user.save
				
				#--Email temporary password to @new_user
				UsersMailer.invitation_mail(current_user, @new_user, @tmp_password).deliver
				
				format.html #renders success message
			else
				logger.info("****Invalid Input")
				format.html { redirect_to '/user/invite', :notice => "Invalid Input" }
			end
    end  
      
 
	end
	
	private
	
	def auth
		if !user_signed_in?
			redirect_to '/perm'
		end
	end
	
	def email_valid(email)
		return true if email =~ /^.+\@.+\..+$/
		return false
	end
	
end
