class Corpus < ActiveRecord::Base
  attr_accessible :description, :language, :name, :upload, :duration, :num_speakers, :speaker_desc, :genre, :annotation, :license, :citation, :hours, :minutes, :seconds
  before_destroy :remove_dirs
  
  before_validation :set_duration
  
  validates :name, :presence => true
  validates :language, :presence => true
  validates :num_speakers, :inclusion => 1..9999
  validates :duration, :inclusion => {:in => 1..86399, :message => "must be at least 1 second and less than 24 hours"}, :if => :times_in_correct_format
  
  attr_accessor :upload_file, :hours, :minutes, :seconds
  
  after_find :set_times
  
  #--Attribute_writer for @upload_file
  def upload=(upload_file)
  	@upload_file = upload_file
  end
  
  #--Removes associated directories
  def remove_dirs
  	FileUtils.rm_rf("corpora.files/#{self.utoken}/");
  	FileUtils.rm_rf("corpora.archives/#{self.utoken}/");
  end
  
  #--Returns human-readable duration
  def human_duration
    Time.at(self.duration).gmtime.strftime('%R:%S')
  end
  
  #--Times format validator function--
  def times_in_correct_format
    hours   = if @hours.nil?    then 0 else @hours.to_i end
    minutes = if @minutes.nil?  then 0 else @minutes.to_i end
    seconds = if @seconds.nil?  then 0 else @seconds.to_i end
    
    if hours < 0 || hours > 23 then
      errors.add(:hours, "Must be between 0 and 23")
      return false
    end
    if minutes < 0 || minutes > 59 then
      errors.add(:minutes, "must be between 0 and 59")
      return false
    end
    if seconds < 0 || seconds > 59 then
      errors.add(:seconds, "must be between 0 and 59")
      return false
    end
    return true
  end
  
  #Sets hours, minutes, seconds
  def set_times
    seconds = self.duration
    @hours    = seconds/3600; seconds %= 3600
    @minutes  = seconds/60; seconds %= 60
    @seconds  = seconds
  end
  #--Sets duration from virtual attributes--
  def set_duration
    @hours    = 0 if @hours.nil?
    @minutes  = 0 if @minutes.nil?
    @seconds  = 0 if @seconds.nil?
    self.duration = @hours.to_i()*3600 + @minutes.to_i()*60 + @seconds.to_i()
  end
  
end