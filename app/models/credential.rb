class Credential < ActiveRecord::Base

  # Associations

  has_and_belongs_to_many :users
  has_many :grants, :dependent => :destroy
  has_many :collections, :through => :grants
  has_one :owner, :class_name => 'User', :foreign_key => :credential_id


  # Validations

  validates :name,
    :presence => true,
    :uniqueness => true,
    :white_space => true
  
  
  # Scopes
  
  scope :ordered, order("name ASC")
  scope :non_personal, lambda {
    personal_ids = joins(:owner).select('credentials.id').map{|c| c.id}
    personal_ids.empty? ? scoped : where("id NOT IN (?)", personal_ids)
  }
  
  # Attributes
  
  def filtered_name
    personal? ? I18n.t('nouns.owner', :count => 1) :  name
  end
  
  def personal?
    !!owner
  end
  
  def list_name
    (name).short(18)
  end
  
end
