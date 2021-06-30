require "json"
require "mongo"
require 'bcrypt'
require "sinatra"
require "sinatra/cookies"
require "sinatra-websocket"


set :bind, "0.0.0.0"
set :server, "thin"
set :sockets, []



class StorageError < StandardError; end
class ExistenceError < StandardError; end


class Pads
	@@open_pads = []

	def self.<<(pad)
		@@open_pads << pad
	end

	def self.include?(name)
		@@open_pads.any? { |pad| pad.lowered_name == name.downcase }
	end

	def self.[](name)
		@@open_pads.select { |pad| pad.lowered_name == name.downcase }[0]
	end

	def self.remove(name)
		@@open_pads.delete(@@open_pads.select { |pad| pad.lowered_name == name.downcase }[0])
	end

	def self.save
		@@open_pads.each { |pad| pad.save }
	end
end



class Pad
	include BCrypt
	attr_reader :name, :lowered_name, :content, :password

	@@padsDB = Mongo::Client.new(ENV["mongouri"], database: "multipad")[:pads]
	@@CHAR_LIMIT = 500_000


	def initialize(name)
		pad = @@padsDB.find({lowered_name: name.downcase}).first

		raise ExistenceError, "Pad #{name} does not exist" if pad == nil

		@name = pad[:name]
		@content = pad[:content]
		@password = pad[:password]
		@has_password = pad[:has_password]
		@lowered_name = pad[:lowered_name]

		Pads << self
	end


	def Pad.create(name, password=nil)
		raise ExistenceError, "Pad #{name} already exists" if @@padsDB.find({lowered_name: name.downcase}).first != nil

		@name = name
		@lowered_name = name.downcase
		@has_password = password != nil
		@password = password == nil ? nil : Password.create(password)
		@content = ""

		@@padsDB.insert_one({
			name: @name,
			lowered_name: @lowered_name,
			has_password: @has_password,
			password: @password,
			content: @content
		})

		Pads << Pad.new(@name)
	end

	def add(addition, selection_start)
		if selection_start < @content.length
			@content[selection_start] = addition + @content[selection_start]
		else
			@content += addition
		end
		
		raise StorageError, "Character limit of #{@@CHAR_LIMIT} exceeded" if @content.length > @@CHAR_LIMIT
	end


	def remove(length, selection_start)
		if selection_start <= @content.length
			@content[selection_start...(selection_start + length)] = ""
		end
	end


	def save
		@@padsDB.update_one(
			{ lowered_name: @lowered_name },
			{ "$set" => { content: @content } }
		)
	end

	def close
		Pads.remove(@name)
		save
	end

	def CHAR_LIMIT
		@@CHAR_LIMIT
	end
end





get "/" do
	erb :index
end


post "/createpad" do
	@pad_name = params[:name]
	@password1 = params[:password1]
	@password2 = params[:password2]
	@has_password = params[:has_password]

	return "Pad name not provided" if @pad_name == nil || @pad_name.length == 0

	if @has_password != nil
		return "You must enter a password" if @password1 == nil || @password1.length == 0
		return "You must re-enter your password" if @password2 == nil || @password2.length == 0

		return "Passwords did not match" if @password1 != @password2
	else
		@password1, @password2 = nil
	end

	begin
		Pad.create(@pad_name, @password1)
	rescue ExistenceError
		return "Pad already exists"
	end

	cookies["#{@pad_name}_password"] = Pads[@pad_name].password if @has_password != nil

	"/pad/#{@pad_name}"
end


post "/openpad" do
	@pad_name = params[:name]

	return "Pad name not provided" if @pad_name.length == 0
	
	begin
		Pad.new(@pad_name)
	rescue ExistenceError
		return "Pad doesn't exist"
	end

	"/pad/#{@pad_name}"
end


get "/pad/:name" do
	@pad_name = params[:name]

	if Pads.include?(@pad_name)
		@pad = Pads[@pad_name]
	else
		begin
			@pad = Pad.new(@pad_name)
		rescue ExistenceError
			return 404
		end
	end
	
	return erb :password if @pad.password != cookies["#{@pad_name}_password"]

	if !request.websocket?
		erb :pad
	else
		request.websocket do |ws|
			ws.onopen do 
				settings.sockets << ws
				EM.next_tick do
					settings.sockets.each do |s| 
						s.send({
							type: "users_online",
							num: settings.sockets.length
						}.to_json)
					end
				end
			end

			ws.onmessage do |msg|
				EM.next_tick do
					data = JSON.parse(msg)
					
					@type = data["type"]
					@data = data["data"]
					@length = data["length"]
					@selection_start = data["selection_start"]
					
					dont_send = false
					if @type == "addition"
						begin
							Pads[@pad_name].add(@data, @selection_start)
						rescue StorageError
							dont_send = true
							msg = {
								type: "error",
								error: "storage",
								length: data["data"].length,
								limit: Pads[@pad_name].CHAR_LIMIT,
								selection_start: @selection_start
							}.to_json
							Pads[@pad_name].remove(data["data"].length, @selection_start)
							ws.send(msg)
						end
					else
						Pads[@pad_name].remove(@length, @selection_start)
					end

					settings.sockets.each { |s| s.send(msg) if s != ws } unless dont_send
				end
			end

			ws.onclose do
				settings.sockets.delete(ws)
				Pads[@pad_name].close if settings.sockets.length == 0

				EM.next_tick do
					settings.sockets.each do |s| 
						s.send({
							type: "users_online",
							num: settings.sockets.length
						}.to_json)
					end
				end
			end
		end
	end
end


post "/pad/:name/password" do
	@pad_name = params[:name]
	@password = params[:password]

	return "You must enter the password" if @password == nil || @password.length == 0

	if Pads.include?(@pad_name)
		@pad = Pads[@pad_name]
	else
		begin
			@pad = Pad.new(@pad_name)
		rescue ExistenceError
			return 404
		end
	end
	
	return "Incorrect password" if BCrypt::Password.new(@pad.password) != @password

	cookies["#{@pad_name}_password"] = @pad.password
	
	"/pad/#{@pad_name}"
end




Thread.new do
	loop do
		Pads.save
		sleep 60
	end
end