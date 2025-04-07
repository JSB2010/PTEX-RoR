module SolidQueue
  # Module for handling database connections in SolidQueue
  module ConnectionHandling
    # Execute a block with proper connection handling
    def with_connection_handling
      # Verify connection before executing the block
      verify_connection
      
      # Execute the block
      yield
    rescue ActiveRecord::ConnectionNotEstablished, PG::ConnectionBad => e
      # Handle connection errors
      Rails.logger.error "Database connection error: #{e.message}"
      Rails.logger.error "Attempting to reconnect..."
      
      # Try to reconnect
      reconnect
      
      # Sleep before retrying
      sleep 5
    rescue => e
      # Handle other errors
      Rails.logger.error "Error in SolidQueue: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Sleep before retrying
      sleep 5
    end
    
    private
    
    # Verify database connection
    def verify_connection
      # Check if connection is established
      unless ActiveRecord::Base.connection.active?
        Rails.logger.info "Database connection is not active, reconnecting..."
        reconnect
      end
    rescue => e
      Rails.logger.error "Error verifying connection: #{e.message}"
      reconnect
    end
    
    # Reconnect to the database
    def reconnect
      begin
        # Close any existing connections
        ActiveRecord::Base.connection_pool.disconnect!
        
        # Establish a new connection
        ActiveRecord::Base.connection_pool.with_connection do |conn|
          # Test the connection
          conn.execute("SELECT 1")
          Rails.logger.info "Successfully reconnected to the database"
        end
      rescue => e
        Rails.logger.error "Failed to reconnect to the database: #{e.message}"
        # Sleep before retrying
        sleep 5
      end
    end
  end
end
