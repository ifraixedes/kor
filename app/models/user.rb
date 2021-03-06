require 'digest/sha2'

class User < ActiveRecord::Base

  include ActiveModel::ForbiddenAttributesProtection


  serialize :login_attempts

  # ----------------------------------------------------------- associations ---
  has_and_belongs_to_many :groups, :class_name => "Credential"
  has_many :created_entities, :class_name => 'Entity', :foreign_key => :creator_id
  has_many :updated_entities, :class_name => 'Entity', :foreign_key => :updater_id
  has_many :user_groups, :dependent => :destroy
  has_many :publishments, :dependent => :destroy
  
  belongs_to :parent, :class_name => "User", :foreign_key => :parent_username, :primary_key => :name
  belongs_to :personal_group, :class_name => 'Credential', :foreign_key => :credential_id
  belongs_to :personal_collection, :class_name => 'Collection', :foreign_key => :collection_id

  # ------------------------------------------------------------- validation ---
  validates :name,
    :presence => true,
    :uniqueness => {:allow_blank => false},
    :format => {:with => /\A[a-zA-Z0-9_\.]+\Z/, :allow_blank => true},
    :white_space => true
  validates :email,
    :presence => true,
    :uniqueness => {:allow_blank => false},
    :format => {:with => /\A[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+[a-zA-Z]{2,4}\Z/i, :allow_blank => true},
    :white_space => true
  validates_format_of :plain_password, :allow_nil => true, :with => /\A(.{5,30})|\Z/
  validates_confirmation_of :plain_password
  
  validate :validate_empty_personal_collection
  validate :validate_existing_parent_user
  
  def validate_empty_personal_collection
    unless make_personal
      if personal_collection
        errors.add :base, :personal_collection_not_empty unless personal_collection.empty?
      end
    end
  end

  def validate_existing_parent_user
    if self.parent_username.present?
      unless User.exists?(:name => self.parent_username)
        errors.add :parent_username, :user_doesnt_exist
      end
    end
  end
  
  
  # -------------------------------------------------------------- callbacks ---
  before_validation(:on => :create) do |model|
    model.generate_password_and_activation_hash
  end
  after_validation :set_expires_at, :create_personal, :add_personal_group
  
  def add_personal_group
    if self.personal_group && !self.personal_group.destroyed?
      unless self.groups.map{|g| g.id}.include?(self.personal_group.id)
        self.groups << self.personal_group
      end
    end
  end
  
  def create_personal
    if make_personal && !personal?
      template = Collection.joins(:owner).first
      
      self.personal_group = Credential.create(:name => name)
      self.personal_collection = Collection.create(:name => name)
      self.groups << self.personal_group
      
      if template
        template.grants.each do |grant|
          self.personal_collection.grant grant.policy, :to => (grant.personal? ? self.personal_group : grant.credential)
        end
      else
        self.personal_collection.grant :all, :to => self.personal_group
      end
    end
    
    if !make_personal && personal?
      self.personal_group.destroy if self.personal_group
      self.personal_collection.destroy if self.personal_collection
    end
  end
  
  def generate_password_and_activation_hash
    self.activation_hash = User.generate_activation_hash if self[:activation_hash].blank?
    self.password = User.generate_password if self[:password].blank?
  end
  
  def set_expires_at
    unless extension.blank?
      case extension
      when 'leave_value'
        nil
      when 'custom'
        write_attribute :expires_at, Kor.now + custom_extension.to_i.days
      when 'never'
        write_attribute :expires_at, nil
      else
        write_attribute :expires_at, Kor.now + extension.to_i.days
      end
    end
  end
  
  
  # ----------------------------------------------------- virtual attributes ---
  attr_accessor :extension
  attr_accessor :custom_extension
  attr_accessor :plain_password
  attr_writer :make_personal
  
  def make_personal
    if @make_personal.nil?
      personal?
    else
      @make_personal
    end
  end
  
  def personal?
    !!self.personal_group && !!self.personal_collection
  end
  
  def list_name
    (name).short(18)
  end
  
  def password=(value)
    self.plain_password = value
    unless value.blank?
      write_attribute :password, User.password_hash_function(value)
    end
  end
  
  def display_name
    full_name.blank? ? name : full_name
  end
  
  def add_login_attempt
    self[:login_attempts] ||= []
    self[:login_attempts] << Kor.now
    self[:login_attempts].shift if self[:login_attempts].size > 3
  end
  
  def admin!
    self.admin = true
    self.collection_admin = true
    self.kind_admin = true
    self.relation_admin = true
    self.user_admin = true
    self.credential_admin = true
    self.authority_group_admin = true
  end
  
  def any_admin?
    admin || collection_admin || kind_admin || relation_admin || user_admin || credential_admin || authority_group_admin
  end

  ["", "collection_", "kind_", "relation_", "user_", "credential_", "authority_group_admin_"].each do |ag|
    define_method "#{ag}admin".to_sym do
      key = "#{ag}admin".to_sym
      self[key] || (self.parent.present? && self.parent[key])
    end

    define_method "#{ag}admin?".to_sym do
      key = "#{ag}admin".to_sym
      self[key] || (self.parent.present? && self.parent[key])
    end

    define_method "#{ag}admin=".to_sym do |value|
      if parent.present? && parent.send("#{ag}admin".to_sym) == !!value
        self["#{ag}admin".to_sym] = nil
      else
        super value
      end
    end
  end
  
  def self.guest
    user = find_by_name('guest')
    user.active? ? user : nil
  end
  
  def guest?
    name == 'guest'
  end
  
  def full_auth
    collections = {}
    Grant.group(:policy).count.each do |policy, c|
      collections[policy] = Kor::Auth.authorized_collections(self, policy).map{|c| c.id}
    end
  
    return {
      :roles => {
        :admin => admin?,
        :collection_admin => collection_admin?,
        :kind_admin => kind_admin?,
        :relation_admin => relation_admin?,
        :user_admin => user_admin?,
        :credential_admin => credential_admin?,
        :authority_group_admin => authority_group_admin
      },
      :collections => collections
    }
  end
  
  # ----------------------------------------------------------------- search ---
  scope :without_predefined, where("name NOT IN (?)", ["admin", "guest"])
  scope :without_admin, where("name NOT LIKE ?", "admin")
  scope :search, lambda { |search_string|
    unless search_string.blank?
      pattern = "%#{search_string}%"
      where('name LIKE ? OR full_name LIKE ? or email LIKE ?', pattern, pattern, pattern)
    else
      scoped
    end
  }
  scope :logged_in_recently, lambda {
    where("last_login > ?", 30.days.ago)
  }
  scope :logged_in_last_year, lambda {
    where("last_login > ?", 1.year.ago) 
  }
  scope :created_recently, lambda {
    where("created_at > ?", 30.days.ago)
  }
  
  def self.guest
    find_by_name('guest')
  end
  
  def self.admin
    unless user = find_by_name('admin')
      raise "There is no admin user"
    end

    user
  end
  
  def self.authenticate(username, password)
    where(:name => username, :password => User.password_hash_function(password)).first
  end
  
  def self.pickup_session_for(id)
    id ? includes(:groups).find(id) : nil
  end


  # ---------------------------------------------------------- miscellaneous ---
  def credential_ids
    groups.map{|c| c.id}
  end
  
  def too_many_login_attempts?
    self[:login_attempts] ||= []
    self[:login_attempts].size == 3 ? self[:login_attempts].first > Kor.now - 1.hour : false
  end
  
  def reset_password
    self.password = User.generate_password
  end

  def User.generate_password
    User.password_hash_function(rand.to_s)[0,6]
  end
  
  def User.generate_activation_hash
    Digest::SHA1.hexdigest(rand.to_s)
  end

  def User.password_hash_function(password)
    Digest::SHA1::hexdigest(password)
  end

  def active
    if self[:active] != nil
      self[:active]
    else
      if parent.present?
        parent.active
      else
        true
      end
    end
  end

  def active?
    active
  end

  def active=(value)
    if parent.present? && parent.active == !!value
      self[:active] = nil
    else
      super
    end
  end

  def expires_at
    self[:expires_at] || if parent.present?
      parent[:expires_at]
    end
  end

  def serializable_hash(options = {})
    super options.merge(:except => [:password, :activation_hash])
  end
  
end
