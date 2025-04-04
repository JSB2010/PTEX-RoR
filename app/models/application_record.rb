# frozen_string_literal: true

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  
  # Include SolidQueue relation methods if available
  include SolidQueue::RelationMethods if defined?(SolidQueue::RelationMethods)
end
