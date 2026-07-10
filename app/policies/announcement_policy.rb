# MiClassrooms Phase 5 Task 4 (Brief §14.1): announcements (home/find-a-room/
# about page banners) are an admin-only console end to end — unlike Note,
# there is no per-unit editor claim that could plausibly extend to a
# workspace-wide announcement slot, so every CRUD action consults only
# `grant.admin?`.
class AnnouncementPolicy < DirectoryPolicy
  def index?  = grant.admin?
  def show?   = grant.admin?
  def new?    = grant.admin?
  def create? = grant.admin?
  def edit?   = grant.admin?
  def update? = grant.admin?
  def destroy? = grant.admin?
end
