class UsersController < ApplicationController
	require 'faye'
	require 'eventmachine'

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
		render :json => User.where("name LIKE ? OR email LIKE ?", q, q)-[current_user()]
	end


	# GET /user/inbox_get
	# params[:mid] = message id
	def inbox_get
		@user = current_user()
		mid = params[:mid]

		unless mid && mid =~ /^\d+$/
			render :json => {:ok => false, :mid => mid, :error => 'message id not valid'}
			return
		end

		mid = mid.to_i

		message = nil
		@user.messages.process do |m|
			if m.id == mid
				message = m
				break
			end
		end

		@user.deleted_messages.process do |m|
			if m.id == mid
				message = m
				break
			end
		end

		unless message
			render :json => {:ok => false, :mid => mid, :error => 'message not found'}
			return
		end

		render :json => {
			:ok => true, 
			:mid => mid,
			:from => message.from, 
			:to => message.to, 
			:topic => message.topic, 
			:body => message.body, 
			:created => message.created_at,
			:time_ago => help.time_ago_in_words(message.created_at),
		}
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

		gone = 0
		@user.sent_messages.process do |message|
			if mids_hash[message.id]
				message.delete
				gone += 1
			end
		end


		moved_to_trash = 0
		@user.received_messages.process do |message|
			if mids_hash[message.id]
				message.delete
				moved_to_trash += 1
			end
		end
		
		render :json => {
			:ok => true, :mids => mids, 
			:permanently_deleted => permanently_deleted,
			:moved_to_trash => moved_to_trash,
			:gone => gone
		}
	end

	# GET /user/send_message
	# params[:to] -- json array of ids
	# params[:subject]
	# params[:body]
	# returns json
	def send_message
		to = params[:to]
		subject = params[:subject]
		body = params[:body]

		me = current_user()

		error = []
		if !subject || subject.blank?
			error << "Subject is invalid"
		end

		if !body || body.blank?
			error << "Body is invalid"
		end

		to.each do |id|
			if !id || id !~ /^\d+$/
				error << "To field is invalid"
				break
			end
		end

		if error.size > 0
			render :json => {:okay => false, :error => error}
			return
		end

		message = nil
		to.each do |id|
			user = User.find_by_id(id)
			next unless user
			message = me.send_message(user, {:topic => subject, :body => body})
		end

		unless message
			render :json => {:ok => false, :error => 'sent message is nil'}
			return
		end

		message_row = render_to_string :partial => 'inbox_message', :layout => false, :locals => {:m => message}
		render :json => {:ok => true, :message_row => message_row}
	end

	# GET /users/inbox
	# Yes, I agree this should all be refactored into a
	# a separate Inbox controller but Meh
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
			@view = :unread
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
