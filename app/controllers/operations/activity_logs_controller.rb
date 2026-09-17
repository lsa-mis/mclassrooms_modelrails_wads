module Operations
  class ActivityLogsController < BaseController
    def index
      authorize [ :operations, ActivityLog ]
      @pagy, page = pagy(:offset, ActivityLog.for_operations_feed.includes(:workspace))
      @activities = page.for_feed
    end
  end
end
