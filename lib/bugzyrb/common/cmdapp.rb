#!/usr/bin/env ruby -w
=begin
  * Name          : cmdapp.rb
  * Description   : some basic command line things
  *               : Moving some methods from todorb.rb here
  * Author        : rkumar
  * Date          : 2010-06-20 11:18 
  * License:       Ruby License

=end
require 'common/sed'

ERRCODE = 1

module Cmdapp

  ## 
  # external dependencies:
  #  @app_default_action - action to run if none specified
  #  @app_file_path - data file we are backing up, or reading into array
  #  @app_serial_path - serial_number file
  ##
  # check whether this action is mapped to some alias and *changes*
  # variables@action and @argv if true.
  # @param [String] action asked by user
  # @param [Array] rest of args on command line
  # @return [Boolean] whether it is mapped or not.
  #
  def check_aliases action, args
    return false unless @aliases
    ret = @aliases[action]
    if ret
      a = ret.shift
      b = [*ret, *args]
      @action = a
      @argv = b
      #puts " #{@action} ; argv: #{@argv} "
      return true
    end
    return false
  end
  ## 
  # runs method after checking if valid or alias.
  # If not found prints help.
  # @return [0, ERRCODE] success 0.
  def run
    @action = @argv[0] || @app_default_action
    @action = @action.downcase


    ret = 0
    @argv.shift
    if respond_to? @action
      ret = send(@action, @argv)
    else
      # check aliases
      if check_aliases @action, @argv
        ret = send(@action, @argv)
      else
        help @argv
        ret = ERRCODE
      end
    end
    ret ||= 0
    ret = 0 if ret != ERRCODE
    return ret
  end
  # not required if using Subcommand
  def help args
    if @actions.nil? 
      if defined? @commands
        unless @commands.empty?
          @actions = @commands
        end
      end
    end
    if @actions
      puts "Actions are "
      @actions.each_pair { |name, val| puts "#{name}\t#{val}" }
    end
    puts " "
    if @aliases
      puts "Aliases are "
      @aliases.each_pair { |name, val| puts "#{name}:\t#{val.join(' ')}" }
    end
    0
  end
  ## 
  def alias_command name, *args
    @aliases ||= {}
    @aliases[name.to_s] = args
  end
  def add_action name, descr
    @actions ||= {}
    @actions[name.to_s] = desc
  end

  ##
  # reads serial_number file, returns serialno for this app
  # and increments the serial number and writes back.
  def _get_serial_number
    require 'fileutils'
    appname = @appname
    filename = @app_serial_path || "serial_numbers"
    h = {}
    # check if serial file existing in curr dir. Else create
    if File.exists?(filename)
      File.open(filename).each { |line|
        #sn = $1 if line.match regex
        x = line.split ":"
        h[x[0]] = x[1].chomp
      }
    end
    sn = h[appname] || 1
    # update the sn in file
    nsn = sn.to_i + 1
    # this will create if not exists in addition to storing if it does
    h[appname] = nsn
    # write back to file
    File.open(filename, "w") do |f|
      h.each_pair {|k,v| f.print "#{k}:#{v}\n"}
    end
    return sn
  end
  ##
  # After doing a redo of the numbering, we need to reset the numbers for that app
  def _set_serial_number number
    appname = @appname
    pattern = Regexp.new "^#{appname}:.*$"
    filename = @app_serial_path || "serial_numbers"
    # during testing redo this file does not exist, so i get errors
    if !File.exists? filename
      _get_serial_number
    end
    _backup filename
    change_row filename, pattern, "#{appname}:#{number}"
  end

  def _backup filename=@app_file_path
    require 'fileutils'
    FileUtils.cp filename, "#{filename}.org"
  end
  def die text
    $stderr.puts text
    exit ERRCODE
  end
  # prints messages to stderr
  # All messages should go to stderr.
  # Keep stdout only for output which can be used by other programs
  def message text
    $stderr.puts text
  end
  # print to stderr only if verbose set
  def verbose text
    message(text) if @options[:verbose]
  end
  # print to stderr only if verbose set
  def warning text
    print_red("WARNING: #{text}") 
  end
  def print_red text
    message "#{RED}#{text}#{CLEAR}"
  end
  def print_green text
    message "#{GREEN}#{text}#{CLEAR}"
  end

  ##
  # load data into array as item and task
  # @see save_array to write
  def load_array
    #return if $valid_array
    $valid_array = false
    @data = []
    File.open(@app_file_path).each do |line|
      # FIXME: use @app_delim
      row = line.chomp.split "\t"
      @data << row
    end
    $valid_array = true
  end
  ## 
  # saves the task array to disk
  # Please use load_array to load, and not populate
  def save_array
    raise "Cannot save array! Please use load_array to load" if $valid_array == false

    File.open(@app_file_path, "w") do |file| 
      # FIXME: use join with @app_delim
      @data.each { |row| file.puts "#{row[0]}\t#{row[1]}" }
    end
  end
  ##
  # retrieve version info updated by jeweler.
  # Typically used by --version option of any command.
  # @return [String, nil] version as string, or nil if file not found
  def version_info
    # thanks to Roger Pack on ruby-forum for how to get to the version
    # file
    filename = File.open(File.dirname(__FILE__) + "/../../VERSION")
    v = nil
    if File.exists?(filename)
      v = File.open(filename).read.chomp if File.exists?(filename)
    #else
      #$stderr.puts "could not locate file #{filename}. " 
      #puts `pwd`
    end
    v
  end

  # reads multiple lines of input until EOF (Ctrl-d)
  # and returns as a string.
  # Add newline after each line
  # @return [String, nil] newline delimited string, or nil
  def get_lines
    lines = nil
    #$stdin.flush
    $stdin.each_line do |line|
      line.chomp!
      if line =~ /^bye$/
        break
      end
      if lines
        lines << "\n" + line
      else
        lines = line
      end
    end
    return lines
  end
  

# edits given text using EDITOR
# @param [String] text to edit
# @return [String, nil] edited string, or nil if no change
def edit_text text
  # 2010-06-29 10:24 
  require 'fileutils'
  require 'tempfile'
  ed = ENV['EDITOR'] || "vim"
  temp = Tempfile.new "tmp"
  File.open(temp,"w"){ |f| f.write text }
  mtime =  File.mtime(temp.path)
  #system("#{ed} #{temp.path}")
  system(ed, temp.path)

  newmtime = File.mtime(temp.path)
  newstr = nil
  if mtime < newmtime
    # check timestamp, if updated ..
    #newstr = ""
    #File.open(temp,"r"){ |f| f.each {|r| newstr << r } }
    newstr = File.read(temp)
    #puts "I got: #{newstr}"
  else
    #puts "user quit without saving"
  end
  return newstr
end

# pipes given string to command
# @param [String] command to pipe data to
# @param [String] data to pipe to command
# @example
#     cmd = %{mail -s "my title" rahul}
#     pipe_output(cmd, "some long text")
# FIXME: not clear how to return error.
# NOTE: this is obviously more portable than using system echo or system cat.
def pipe_output (pipeto, str)
  #pipeto = '/usr/sbin/sendmail -t'
  #pipeto = %q{mail -s "my title" rahul}
  if pipeto != nil  # i was taking pipeto from a hash, so checking
    proc = IO.popen(pipeto, "w+")
    proc.puts str
    proc.close_write
    #puts proc.gets
  end
end
##
# reads up template, and substirutes values from myhash
# @param [String] template text
# @param [Hash] values to replace in template
# @return [String] template output
# NOTE: probably better to use rdoc/template which can handle arrays as well.
def template_replace template, myhash
  #tmpltext=File::read(template);

  t = template.dup
  t.gsub!( /##(.*?)##/ ) {
    #raise "Key '#{$1}' found in template but the value has not been set" unless ( myhash.has_key?( $1 ) )
    myhash[ $1 ].to_s
  }
  t
end
#------------------------------------------------------------
# these 2 methods deal with with maintaining readline history
# for various columns. _read reads up any earlier values
# so user can select from them.
# _save saves the values for future use.
#------------------------------------------------------------
# for a given column, check if there's any previous data
# in our cache, and put in readlines history so user can 
# use or edit. Also put default value in history.
# @param [String] name of column for maintaining cache
# @param [String] default data for user to recall, or edit
def history_read column, default=nil
  values = []
  oldstr = ""
  if !defined? $history_hash
    require 'readline'
    require 'yaml'
    filename = File.expand_path "~/.bugzy_history.yml"
    $history_filename = filename
    # if file exists with values push them into history
    if File.exists? filename
      $history_hash = YAML::load( File.open( filename ) )
    else
      $history_hash = Hash.new
    end
  end
  values.push(*$history_hash[column]) if $history_hash.has_key? column
  # push existing value into history also, so it can be edited
  values.push(default) if default
  values.uniq!
  Readline::HISTORY.clear # else previous values of other fields also come in
  Readline::HISTORY.push(*values) unless values.empty?
  #puts Readline::HISTORY.to_a
end
## 
# update our cache with str if not present in cache already
# @param [String] name of column for maintaining cache
# @param [String] str : data just entered by user
#
def history_save column, str
  return if str.nil? or str == ""
  if $history_hash.has_key? column
    return if $history_hash[column].include? str
  end
  ($history_hash[column] ||= []) << str
  filename = $history_filename
  File.open( filename, 'w' ) do |f|
    f << $history_hash.to_yaml
  end
end
  # separates args to list-like operations
  # +xxx means xxx should match in output
  # -xxx means xxx should not exist in output
  # @param [Array] list of search terms to match or not-match
  # @return [Array, Array] array of terms that should match, and array of terms
  # that should not match.
  def _list_args args
    incl = []
    excl = []
    args.each do |e| 
      if e[0] == '+'
        incl << e[1..-1]
      elsif  e[0] == '-'
        excl << e[1..-1]
      else
        incl << e
      end
    end
    incl = nil if incl.empty?
    excl = nil if excl.empty?
    return incl, excl
  end
  ##  
  # creates a regexp and for each row returns the row and the regexp
  # you can use the regexp on whatever part of the row you want to match or reject
  def filter_rows rows, incl
    if incl
      incl_str = incl.join "|"
      r = Regexp.new incl_str
      #rows = rows.select { |row| row['title'] =~ r }
      rows = rows.select { |row| yield(row, r) }
    end
    rows
  end



end
