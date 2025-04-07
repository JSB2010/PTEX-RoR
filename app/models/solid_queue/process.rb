# frozen_string_literal: true

module SolidQueue
  class Process < ApplicationRecord
    self.table_name = "solid_queue_processes"

    # Scopes
    scope :active, -> { where("last_heartbeat_at >= ?", 30.seconds.ago) }
    scope :stale, -> { where("last_heartbeat_at < ?", 30.seconds.ago) }

    # Associations
    belongs_to :supervisor, class_name: "Process", optional: true
    has_many :supervisees, class_name: "Process", foreign_key: :supervisor_id
    has_many :claimed_executions, class_name: 'SolidQueue::ClaimedExecution', dependent: :destroy

    # Validations
    validates :kind, presence: true
    validates :name, presence: true, uniqueness: { scope: :supervisor_id }
    validates :pid, presence: true
    validates :hostname, presence: true

    def self.register(kind:, name: nil, pid: nil, hostname: nil, supervisor: nil, metadata: nil)
      create!(
        kind: kind,
        name: name || "#{kind}-#{SecureRandom.hex(6)}",
        pid: pid || ::Process.pid,
        hostname: hostname || Socket.gethostname,
        supervisor_id: supervisor&.id,
        metadata: metadata,
        last_heartbeat_at: Time.current
      )
    end

    def self.current
      find_by(pid: ::Process.pid)
    end

    def self.prune
      where('last_heartbeat_at < ?', 5.minutes.ago).destroy_all
    end

    def supervisees
      self.class.where(supervisor_id: id)
    end

    def update_heartbeat!
      update!(last_heartbeat_at: Time.current)
    rescue ActiveRecord::StaleObjectError
      reload
      retry
    end

    # Method for compatibility
    def heartbeat
      update_heartbeat!
    end

    def deregister
      transaction do
        claimed_executions.delete_all
        supervisees.destroy_all
        destroy
      end
    end

    def alive?
      return false unless pid

      begin
        ::Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end
    end

    def stale?
      !alive?
    end
  end
end