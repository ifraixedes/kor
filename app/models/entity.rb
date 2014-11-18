# encoding: utf-8

class Entity < ActiveRecord::Base

  # Settings
  
  serialize :external_references
  
  acts_as_taggable_on :tags
  
  self.per_page = 10
  
  # Associations
  
  belongs_to :creator, :class_name => "User", :foreign_key => :creator_id
  belongs_to :updater, :class_name => "User", :foreign_key => :updater_id
  belongs_to :kind
 
  has_many :datings, :class_name => "EntityDating", :dependent => :destroy
  
  has_many :ratings, :class_name => 'Api::Rating'
 
  belongs_to :medium, :dependent => :destroy

  belongs_to :collection
  
  has_and_belongs_to_many :system_groups
  has_and_belongs_to_many :authority_groups
  has_and_belongs_to_many :user_groups

  has_many :relationships,
    :finder_sql => Proc.new {
      "SELECT DISTINCT relationships.*
       FROM relationships 
       WHERE (from_id = #{id} OR to_id = #{id})"
    },
    :class_name => "Relationship",
    :dependent => :destroy do
      def only(options = {})
        options.reverse_merge!( :kind => nil, :relation_names => nil )

        result = self
        if options[:kind]
          result = result.select do |rs|
            Kind.find_ids(options[:kind]).include?( rs.other_entity(proxy_association.owner).kind_id )
          end
        end

        if options[:relation_names]
          result = result.select do |rs|
            Array(options[:relation_names]).include?( rs.relation_name_for_entity(proxy_association.owner) )
          end
        end

        result.sort do |x,y|
          x_name = x.other_entity(proxy_association.owner).display_name || ""
          y_name = y.other_entity(proxy_association.owner).display_name || ""
          x_name.downcase <=> y_name.downcase
        end
      end

      def except(options = {})
        options.reverse_merge!(:kind => [], :relation_names => [])
        only( 
          :kind => Kind.all_ids - Kind.find_ids(options[:kind]),
          :relation_names => Relation.all.collect{|r| [r.name, r.reverse_name]}.flatten - options[:relation_names]
        )
      end
      
      def authorized(user, policies)
        collection_ids = Auth::Authorization.authorized_collections(user, policies).map{|c| c.id}
        
        self.select do |rs|
          collection_ids.include? rs.other_entity(proxy_association.owner).collection_id
        end
      end
      
      def grouped
        except(:kind => Kind.medium_kind.id).group_by do |r| 
          r.relation_name_for_entity(proxy_association.owner)
        end
      end
    end
    
  def grouped_related_entities(user, policies, options = {})
    options.reverse_merge!(:media => :no, :limit => false)
  
    relation_conditions =  "(from_id = #{self[:id]} OR to_id = #{self[:id]})"
    collection_conditions = "IF(from_id = #{self[:id]},tos_relationships.collection_id,entities.collection_id) IN (?)"
    media_conditions = case options[:media]
      when :no then "IF(from_id = #{self[:id]},tos_relationships.kind_id,entities.kind_id) != #{Kind.medium_kind.id} AND"
      when :yes then "IF(from_id = #{self[:id]},tos_relationships.kind_id,entities.kind_id) = #{Kind.medium_kind.id} AND"
      when :both then ""
    end
    
    relationships = Relationship.includes(:from, :relation, :to).order("tos_relationships.name, entities.name")
    relationships = relationships.where(
      "#{media_conditions} #{relation_conditions} AND #{collection_conditions}",
      Auth::Authorization.authorized_collections(user, policies).map{|c| c.id}
    )
    
    relationships.group_by{|r| r.relation_name_for_entity(self)}
  end
  
  def try_again
    Relationship.find_by_sql("
      SELECT
        IF(r1.from_id = #{self.id}, 1, 0) AS normal,
        IF(r1.from_id = #{self.id}, r1.name, r1.reverse_name) AS name,
        IF(r1.from_id = #{self.id}, e1.name, er1.name) 
      FROM relationships r1
        JOIN entities e1 ON e1.id = r1.from_id
        JOIN entities er1 ON er1.id = r1.to_id
    ")
  end
  

  # Nesting
  
  accepts_nested_attributes_for :medium

  
  # Validation

  validates_associated :datings

  validates_presence_of :kind
  validates_presence_of :uuid
  validates_inclusion_of :no_name_statement, :allow_blank => true, :in => [ 'unknown', 'not_available', 'empty_name', 'enter_name' ]
  validates_presence_of :name, :if => :needs_name?
  validates_uniqueness_of :name, :scope => [ :kind_id, :distinct_name ], :allow_blank => true
  validates_uniqueness_of :distinct_name, :scope => [ :kind_id, :name ], :allow_blank => true
  validates_presence_of :collection_id
  
  validate :validate_distinct_name_needed, :validate_attachment, :attached_file

  def attached_file
    if is_medium?
      if medium
        unless medium.document.file? || medium.image.file?
          medium.errors.add :document, :needs_file
          medium.errors.add :image, :needs_file
        end
      else
        errors.add :medium, :needs_medium
      end
    end
  end
  
  def validate_distinct_name_needed
    if has_name_duplicates?
      duplicate_collection = find_name_duplicates.first.collection
      
      if duplicate_collection.id != self.collection_id
        message = I18n.t('activerecord.errors.messages.needed_for_disambiguation', :collection => duplicate_collection.name)
        errors.add :distinct_name, message
      else
        errors.add :distinct_name
      end
    end
  end
  
  def simple_errors
    result = []
    errors.each do |a, m|
      result << [I18n.t(a, :scope => [:activerecord, :attributes]), m] unless a == 'medium'
    end
    result
  end
  
  
  # Attachment

  def dataset
    get_attachment_value('dataset', {})
  end
  
  def dataset=(values)
    set_attachment_value('dataset', values)
  end
  
  def attachment
    @attachment ||= Kor::Attachment.new(self)
  end
  
  def save_attachment
    attachment.save
  end
  
  def save_id_in_attachment
    attachment.entity_id = id
    attachment.save
  end
  
  def destroy_attachment
    attachment.destroy
  end
  
  def validate_attachment
    attachment.validate
  end
  
  def get_attachment_value(scope, default = nil)
    if kind
      # kind.entities.build() does not trigger the kind= writer, so no 
      # attributes are taken from @after_kind_attributes
      self.kind = kind unless (@after_kind_attributes || {}).empty?
    
      attachment.document[scope.to_s] ||= default
    else
      @after_kind_attributes[scope.to_sym] || default
    end
  end
  
  def set_attachment_value(scope, value)
    if kind
      attachment.document[scope.to_s] = value
    else
      @after_kind_attributes ||= {}
      @after_kind_attributes[scope.to_sym] = value
    end
  end
  
  
  # Callbacks
  
  before_validation :generate_uuid, :sanitize_distinct_name
  before_save :generate_uuid, :add_to_user_group, :save_attachment
  after_save :save_id_in_attachment
  after_update :save_datings
  before_destroy :destroy_attachment
  after_commit :update_elastic
  
  def sanitize_distinct_name
    self.distinct_name = nil if self.distinct_name == ""
  end
  
  def generate_uuid
    self.uuid ||= UUIDTools::UUID.random_create.to_s
  end
  
  def save_datings
    datings.each do |dating|
      dating.save(:validate => false)
    end
  end
  
  def update_elastic
    unless is_medium?
      if destroyed?
        Kor::Elastic.drop self
      else
        Kor::Elastic.index self, :full => true
      end
    end
  end
  
  
  # Synonyms
  
  def synonyms
    get_attachment_value('synonyms', []).uniq
  end
  
  def synonyms=(values)
    values = values.split(', ') if values.is_a?(String)
    set_attachment_value('synonyms', values)
  end
  
  
  # Properties
  
  def properties
    get_attachment_value('properties', [])
  end
  
  def properties=(values)
    set_attachment_value('properties', values)
  end
  
  
  # Attributes
  
  alias :old_kind= :kind=
  
  def kind_id=(value)
    self[:kind_id] = value
    self.attributes = @after_kind_attributes
    @after_kind_attributes = {}
  end
  
  def kind=(value)
    self.old_kind = value
    self.attributes = @after_kind_attributes
    @after_kind_attributes = {}
  end
  
  def recent?
    @recent
  end
  
  def remember_recent!
    @recent = true
  end
  
  
  # ---------------------------------------------------------- miscellaneous ---
  attr_accessor :user_group_id
  def add_to_user_group
    if user_group_id
      user_group = UserGroup.find(user_group_id)
      self.user_group_id = nil
      user_group.add_entities self
    end
  end
  
  def mark_invalid
    SystemGroup.find_or_create_by_name('invalid').add_entities self
  end

  def mark_valid
    SystemGroup.find_or_create_by_name('invalid').remove_entities self
  end
  
  
  ############################ user related ####################################

  def last_updated_by
    updater || creator
  end
  
  scope :allowed, lambda { |user, policy|
    collections = Auth::Authorization.authorized_collections(user, policy)
    where("collection_id IN (?)", collections.map{|c| c.id})
  }
  

  ############################ comment related #################################

  def html_comment
    red_cloth = RedCloth.new(self.comment || "")
    red_cloth.sanitize_html = true
    red_cloth.to_html
  end
  
  
  ############################ relationships ###################################
  
  def degree
    Relationship.where("from_id = ? OR to_id = ?", self.id, self.id).count
  end
  
  def related_entities(options = {})
    options.reverse_merge!(:relation_names => nil)
    relationships.only(options).map{|r| r.other_entity(self)}
  end
  
  def related(options = {})
    options.reverse_merge!(
      :assume => :primary,
      :search => :media
    )
    
    if options[:assume] == :media
      if options[:search] == :primary
        related_entities(:relation_names => Relation.primary_relation_names)
      else
        raise "invalid options or invalid combination: #{options.inspect}"
      end
    elsif options[:assume] == :primary
      if options[:search] == :media
        related_entities(:relation_names => Relation.reverse_primary_relation_names)
      elsif options[:search] == :secondary 
        related_entities(:relation_names => Relation.secondary_relation_names)
      end 
    elsif options[:assume] == :secondary
      if options[:search] == :primary
        related_entities(:relation_names => Relation.reverse_secondary_relation_names)
      elsif options[:search] == :media
        related(:assume => :secondary, :search => :primary).map do |e|
          e.related(:assume => :primary, :search => :media)
        end.flatten.uniq
      end
    else
      raise "invalid options or invalid combination: #{options.inspect}"
    end
  end
  
  
  ############################ naming ##########################################
  
  def medium_hash
    self.medium ? self.medium.datahash : nil
  end
  
  def kind_name(options = {})
    options.reverse_merge!(:include_subtype => true)
    
    result = is_medium? ? medium.content_type : kind.name
    if options[:include_subtype] && !self[:subtype].blank?
       result += " (#{self[:subtype]})"
    end
    result
  end
  
  def save_with_serial
    while has_name_duplicates?
      self.distinct_name ||= ""
      if self.distinct_name.match(/– \d+$/)
        serial = distinct_name.match(/\d+$/)[0].to_i + 1
        self.distinct_name.gsub! /\d+$/, serial.to_s
      elsif self.distinct_name.match(/^[\d]+$/)
        serial = self.distinct_name.to_i + 1
        self.distinct_name = serial.to_s
      else
        if self.distinct_name.blank?
          self.distinct_name = "2"
        else
          self.distinct_name += " – 2"
        end
      end
    end
    
    save
  end
  
  def has_name_duplicates?
    find_name_duplicates.count > 0
  end
  
  def find_name_duplicates
    if is_medium?
      []
    else
      result = self.class.where(:name => name, :distinct_name => distinct_name, :kind_id => kind_id)
      new_record? ? result : result.where("id != ?", id)
    end
  end

  def find_others_by_distinct_name
    distinct_name.blank? ? [] :
      Entity.where(
        [ "(name LIKE ? OR distinct_name LIKE ?) AND kind_id = ? AND id != ?",
        distinct_name, distinct_name, kind_id, id || -1 ]
      )
  end

#  def needs_distinct_name?
#    unless needs_name?
#      false
#    else
#      Entity.where(
#        ["name LIKE ? and kind_id LIKE ? and id != ?",
#          name, kind_id, id || -1
#        ]
#      ).first
#    end
#  end

  def needs_name?
    !is_medium? && no_name_statement == 'enter_name'
  end

  def has_distinct_name?
    distinct_name.blank? ? false : true
  end

  def display_name
    if is_medium?
      "#{Medium.model_name.human} #{id}"
    elsif no_name_statement == 'enter_name'
      distinct_name.blank? ? name : "#{name} (#{distinct_name})".strip
    else
      I18n.t('values.no_name_statements.' + no_name_statement).capitalize_first_letter
    end
  end

  def no_name_statement
    read_attribute(:no_name_statement) || 'enter_name'
  end
  
  def find_equally_named(distinct = false)
    result = Entity.where("kind_id = ?", kind_id).where("name = ?", name)
    distinct ? result.where("distinct_name = ?", distinct_name) : result
  end

  
  ############################ kind related ####################################

  def is_medium?
    (self[:medium_id] || self.medium || self.kind == Kind.medium_kind) ? true : false
  end


  #----------------------------------------------------- external references ---
  # TODO: Nasty hack, remove as soon as MongoDB is out
  def external_references
    self[:external_references] ||= {}
    self[:external_references].each do |k, v|
      self[:external_references][k] = v.force_encoding("utf-8")
    end
    self[:external_references]
  end
  
  def external_references=(attributes)
    self[:external_references] = external_references.merge(attributes || {})
  end
  
  ############################ dating ##########################################

  def new_datings_attributes=(values)
    values.each do |v|
      datings.build v
    end
  end

  def existing_datings_attributes=(values)
    datings.reject(&:new_record?).each do |d|
      attributes = values[d.id.to_s]
      if attributes
        d.attributes = attributes
      else
        datings.delete(d)
      end
    end
  end


  ############################ image related ###################################
  def images(user)
    @images ||= grouped_related_entities(user, :view, :media => :yes).values.flatten.map{|r| r.other_entity(self)}.uniq
  end

  def media(user)
    @media ||= grouped_related_entities(user, :view, :media => :yes).values.flatten.map{|r| r.other_entity(self)}.uniq
  end

  def has_images?(user)
    !images(user).empty?
  end


  # ----------------------------------------------------------------- search ---
  def self.filtered_tag_counts(term, options = {})
    options.reverse_merge!(:limit => 10)
    
    Entity.
      tag_counts(:order => 'count DESC', :limit => options[:limit]).
      where('tags.name LIKE ?', "%#{term}%")
  end
  
  attr_writer :search_attributes

  def search_attributes(section = nil)
    if section
      ( @search_attributes || {} )[section] || {}
    else
      @search_attributes
    end
  end
  
  
  def self.find_by_kind_and_naming(kind_id, naming)
    find_by_sql "SELECT entities.* from entities
      LEFT JOIN synonyms on entities.id = synonyms.entity_id
      WHERE
        entities.kind_id = #{kind_id} AND (
          synonyms.name LIKE '#{naming}' OR
          entities.name LIKE '#{naming}'
        )
    "
  end

  # Finds all entities given in <tt>ids</tt> and keeps the same order as the
  # ids in the parameter. Ids which refer to non existing entities are
  # transparently ignored.
  def self.find_all_by_id_keep_order(ids)
    tmp_entities = find_all_by_id(ids)
    Array(ids).collect{|id| tmp_entities.find{|e| e.id.to_i == id.to_i } }.reject{|e| e.blank? }
  end
  
  def self.find_all_by_uuid_keep_order(uuids)
    tmp_entities = find_all_by_uuid(uuids)
    Array(uuids).collect{|uuid| tmp_entities.find{|e| e.uuid == uuid } }.reject{|e| e.blank? }
  end
  
  # TODO the scopes are not combinable e.g. id-conditions overwrite each other
  scope :within_collections, lambda {|ids| ids ? where("collection_id IN (?)", ids) : scoped }
  scope :recently_updated, lambda {|*args| where("updated_at > ?", (args.first || 2.weeks).ago) }
  scope :latest, lambda {|*args| where("created_at > ?", (args.first || 2.weeks).ago) }
  scope :searcheable, lambda { where("kind_id != ?", Kind.medium_kind.id) }
  scope :media, lambda { where("kind_id = ?", Kind.medium_kind.id) }
  scope :without_media, lambda { where("kind_id != ?", Kind.medium_kind.id) }
  scope :alphabetically, order("name asc, distinct_name asc")
  scope :newest_first, order("created_at DESC")
  scope :globally_identified_by, lambda {|uuid| uuid.blank? ? scoped : where(:uuid => uuid) }
  scope :is_a, lambda { |kind_id|
    kind = Kind.find_by_name(kind_id.to_s)
    kind ||= Kind.find_by_id(kind_id)
    kind ? where(:kind_id => kind.id) : scoped
  }
  scope :named_exactly_like, lambda {|value| where("name like :value or concat(name,' (',distinct_name,')') like :value", :value => value) }
  scope :valid, lambda { |valid|
    ids = Tag.invalid_tag.entities.collect{|e| e.id}
    valid ?
      where('id NOT IN (?)', ids) :
      where(:id => ids)
  }
  scope :named_like, lambda { |pattern|
    if pattern.blank?
      {}
    else
      pattern_query = pattern.tokenize.map{ |token| "name LIKE ?"}.join(" AND ")
      pattern_values = pattern.tokenize.map{ |token| "%" + token + "%" }

      entity_ids = Kor::Attachment.find_by_synonym(pattern)
      entity_ids += Entity.where([pattern_query.gsub('name','distinct_name')] + pattern_values ).collect{|e| e.id}

      id_query = entity_ids.blank? ? "" : "OR entities.id IN (?)"
      entity_id_bind_variables = entity_ids.blank? ? [] : [ entity_ids ]

      where(["(#{pattern_query}) #{id_query}"] + pattern_values + entity_id_bind_variables)
    end
  }
  scope :has_property, lambda { |properties|
    if properties.blank?
      {}
    else
      entity_ids = Kor::Attachment.find_by_property(properties)
      entity_ids ? where("entities.id IN (?)", entity_ids.uniq) : scoped
    end
  }
  scope :related_to, lambda { |relationships|
    entity_ids = nil
    
    (relationships || []).each do |criterium|
      to_entities = Entity.named_like(criterium[:entity_name])
      rs = Relationship.find_by_participants_and_relation_name(
        :relation_name => criterium[:relation_name],
        :to_id => to_entities.collect{|e| e.id}
      )
      
      current_ids = rs.map{|r| r.from_entity_for_relation_name(criterium[:relation_name]).id }
      entity_ids ||= current_ids  
      entity_ids &= current_ids
    end
    
    entity_ids ? where("entities.id IN (?)", entity_ids.uniq) : scoped
  }
  scope :dated_in, lambda {|dating|
    dating.blank? ? scoped : where("entities.id IN (?)", EntityDating.between(dating).collect{|ed| ed.entity_id }.uniq)
  }
  scope :dataset_attributes, lambda { |dataset|
    query = {}
    (dataset || {}).each do |k, v|
      query["dataset.#{k}"] = /#{v}/i unless v.blank?
    end
    
    if query.empty?
      scoped
    else
      ids = Kor::Attachment.find query
      where("entities.id IN (?)", ids)
    end
  }
  scope :gallery, lambda { |search_string|
    if search_string.blank? || search_string.size < 3
      where(:kind_id => Kind.medium_kind.id)
    else
      reverse_primary_relations = Relation.reverse_primary_relation_names
      reverse_secondary_relations = Relation.reverse_secondary_relation_names
      
      match_ids = Entity.named_like(search_string).map{|e| e.id}
      match_ids += Investigator.new.related_entities_for(match_ids, reverse_secondary_relations)
      image_ids = Investigator.new.related_entities_for(match_ids, reverse_primary_relations, Kind.medium_kind.id)
      
      image_ids = (image_ids.is_a?(Hash) ? image_ids.values.flatten : image_ids).uniq
      
      where("entities.id IN (?) AND kind_id = ?", image_ids.uniq, Kind.medium_kind.id)
    end
  }
  
  scope :load_fully, joins(:kind, :collection)
  
end
