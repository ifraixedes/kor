class ExceptionLog < ActiveRecord::Base
  serialize :params
  
  scope :no_routing_errors, where("kind NOT LIKE 'ActionController::RoutingError'")
end
