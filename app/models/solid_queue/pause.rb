module SolidQueue
  class Pause < SolidQueue::Record
    self.table_name = "solid_queue_pauses"
  end
end