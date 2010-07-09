#!/usr/bin/env ruby -w
require 'rubygems'
require 'sqlite3'
require 'pp'
require 'arrayfields'
module Database
  class DB
    attr_accessor :db

    def initialize dbname="bugzy.sqlite"
      raise "#{dbname} does not exist. Try --help" unless File.exists? dbname
      @db = SQLite3::Database.new(dbname)
      $now = Time.now
      $num = rand(100)
      $default_user = ENV['LOGNAME'] || ENV['USER']
    end

    # returns many rows 
    # @param [Fixnum] id for table with 1:n rows
    # @return [Array, nil] array if rows, else nil
    def select table
      #puts " --- #{table} ---  "
      @db.type_translation = true
      rows = []
      @db.execute( "select * from #{table} " ) do |row|
        if block_given?
          yield row
        else
          rows << row
        end
      end
      return nil if rows.empty?
      return rows
    end
    # returns many rows 
    # @param [String] sql statement
    # @return [Array, nil] array if rows, else nil
    def run text
      #puts " --- #{text} ---  "
      @db.type_translation = true
      rows = []
      @db.execute( text ) do |row|
        if block_given?
          yield row
        else
          rows << row
        end
      end
      return nil if rows.empty?
      return rows
    end
    def select_where table, *wherecond
      #puts " --- #{table} --- #{wherecond} "
      @db.type_translation = true
      wherestr = nil
      rows = []
      if wherecond and !wherecond.empty?
        fields, values = separate_field_values wherecond
        #wherestr = "" unless wherestr
        wherestr = " where #{fields.join(" and ")} "
        if wherestr
          #puts " wherestr #{wherestr}, #{values} "
          #stmt = @db.prepare("select * from #{table} #{wherestr} ", *values)
          @db.execute( "select * from #{table} #{wherestr}", *values  ) do |row|
            if block_given?
              yield row
            else
              rows << row
            end
          end
        end
      end
      return nil if rows.empty?
      return rows
    end
  ## takes a hash and creates an insert statement for table and inserts data.
  # Advantage is that as we add columns, this will add the column to the insert, so we
  # don't need to keep modifying in many places.
  # @param [String] name of table to insert data into
  # @param [Hash] values to insert, keys must be table column names
  # @return [Fixnum] newly inserted rowid
  def table_insert_hash table, hash
    str = "INSERT INTO #{table} ("
    qstr = [] # question marks
    fields = [] # field names
    bind_vars = [] # values to insert
    hash.each_pair { |name, val| 
      fields << name
      bind_vars << val
      qstr << "?"
    }
    fstr = fields.join(",")
    str << fstr
    str << ") values ("
    str << qstr.join(",")
    str << ")"
    #puts str
    @db.execute(str, *bind_vars)
    rowid = @db.get_first_value( "select last_insert_rowid();")
    return rowid
  end
  def max_bug_id table="bugs"
    id = @db.get_first_value( "select max(id) from #{table};")
    return id
  end
  def sql_comments_insert id, comment, created_by = $default_user
    #date_created = date_cr | Time.now
    @db.execute("insert into comments (id, comment, created_by) values (?,?,?)", id, comment, created_by ) 
    rowid = @db.get_first_value( "select last_insert_rowid();")
    return rowid
  end
  def sql_logs_insert id, field, log, created_by = $default_user
    #date_created = date_cr | Time.now
    @db.execute("insert into log (id, field, log, created_by) values (?,?,?,?)", id, field, log, created_by ) 
  end
  def sql_delete_bug id
    message "deleting #{id}"
    @db.execute( "delete from bugs where id = ?", id )
    @db.execute( "delete from comments where id = ?", id )
    @db.execute( "delete from log where id = ?", id )
  end


    ##
    # update a row from bugs based on id, giving one fieldname and value
    # @param [Fixnum] id unique key
    # @param [String] fieldname 
    # @param [String] value to update
    # @example sql_update "bugs", 9, :name, "Roger"
    def sql_update table, id, field, value
      @db.execute( "update #{table} set #{field} = ?, date_modified = ? where id = ?", value,$now, id)
    end

    # update a row from bugs based on id, can give multiple fieldnames and values
    # @param [Fixnum] id unique key
    # @return [Array] alternating fieldname and value
    # @example sql_bugs_update_mult 9, :name, "Roger", :age, 29, :country, "SWI"
    def sql_bugs_update_mult id, *fv
      fields = []
      values = []
      fv << "date_modified"
      fv << $now
      fv.each_with_index do |f, i| 
        if i % 2 == 0
          fields << "#{f} = ?"
        else
          values << f
        end
      end

      print( "update bugs set #{fields.join(" ,")} where id = ?", *values, id)
      @db.execute( "update bugs set #{fields.join(" ,")} where id = ?", *values, id)
    end
    # 
    # return a single row from table based on rowid
    # @param [String] table name
    # @param [Fixnum] rowid
    # @return [Array] resultset (based on arrayfield)
    def sql_select_rowid table, id
      # @db.results_as_hash = true
      return nil if id.nil? or table.nil?
      row = @db.get_first_row( "select * from #{table} where rowid = ?", id )
      return row
    end

    def separate_field_values array
      fields = []
      values = []
      array.each_with_index do |f, i| 
        if i % 2 == 0
          fields << "#{f} = ?"
        else
          values << f
        end
      end
      return fields, values
    end
    def dummy
       id = $num
       status = "open" 
       severity = "critical" 
       type = "bug" 
       assigned_to = "rahul" 
       start_date = $now
       due_date = $now
       comment_count = 0
       priority = "P1" 
       title = "some title" 
       description = "Some long text fro this bug too" 
       fix = nil #"Some long text" 
       date_created = $now
       date_modified = $now
       created_by = $default_user
       bugs_insert(status, severity, type, assigned_to, start_date, due_date, comment_count, priority, title, description, fix, created_by)
      #bugs_insert(id, status, severity, type, assigned_to, start_date, due_date, comment_count, priority, title, description, fix, date_created, date_modified)
    end

  end # class
end # module
if __FILE__ == $PROGRAM_NAME
  include Database
  # some tests. change bugs with real name
  db = DB.new
  db.dummy
  puts  "\n------------ all row -----\n"
  #db.select "bugs" do |r|
    #puts r
    ##puts r.join(" | ")
  #end
  res = db.select "bugs" 
  if res
    puts "count: #{res.count}"
    #puts res.public_methods
    res.each do |e| 
      puts e.join(" | ")
    end
  end
  db.sql_update "bugs", 1, "fix", "A fix added at #{$now}"
  db.sql_bugs_update_mult 1, "title", "a new title #{$num}", "description", "a new description #{$num}"
  puts  "\n------------ one row -----\n "
  db.select_where "bugs", "id", 1 do |r|
    puts r.join(" | ")
  end

end # if