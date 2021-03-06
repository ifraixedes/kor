class UserGroupsController < GroupsController
  layout 'normal_small'
  
  def mark
    @user_group = UserGroup.owned_by(current_user).find_by_id(params[:id])
    @user_group ||= UserGroup.shared.find(params[:id])
    ids = @user_group.entities.allowed(current_user, :view).map{|e| e.id}
    
    session[:clipboard] ||= Array.new
    session[:clipboard] = (session[:clipboard] + ids).uniq
    
    flash[:notice] = I18n.t("objects.marked_entities_success")
    
    redirect_to :action => 'show'
  end
  
  def download_images
    @user_group = UserGroup.find(params[:id])
    
    if @user_group.owner == current_user or @user_group.shared
      @entities = @user_group.entities.allowed(current_user, :view).media
      
      zip_download @user_group, @entities
    else
      flash[:error] = I18n.t('errors.access_denied')
      redirect_to denied_path
    end
  end

  def add_to
    @user_group = UserGroup.owned_by(current_user).find(params[:id])
    entities = viewable_entities.find ArgumentArray(params[:entity_ids])
    @user_group.add_entities(entities)
    
    redirect_to @user_group
  end

  def remove_from
    @user_group = UserGroup.owned_by(current_user).find(params[:id])
    entities = viewable_entities.find ArgumentArray(params[:entity_ids])
    @user_group.remove_entities(entities)

    redirect_to @user_group
  end
  
  def share
    @user_group = if current_user.admin?
      UserGroup.find(params[:id])
    else
      UserGroup.owned_by(current_user).find(params[:id])
    end

    @user_group.shared = true
    @user_group.save
    flash[:notice] = I18n.t('objects.shared_success', :o => @user_group.name)
    redirect_to :back
  end
  
  def unshare
    @user_group = if current_user.admin?
      UserGroup.find(params[:id])
    else
      UserGroup.owned_by(current_user).find(params[:id])
    end

    @user_group.shared = false
    @user_group.save
    flash[:notice] = I18n.t('objects.unshared_success', :o => @user_group.name)
    redirect_to :back
  end
  
  def shared
    @user_groups = UserGroup.shared
  end

  def index
    @user_groups = UserGroup.owned_by(current_user)
    
    if params[:term]
      @user_groups = @user_groups.named_like(params[:term])
    end
    
    respond_to do |format|
      format.html
      format.json do
        render :json => @user_groups.map { |ug|
          {:label => "#{ug.name} (#{ug.entities.count} #{Entity.model_name.human(:count => :other)})", :value => ug.name}
        }
      end
    end
  end

  def show
    @user_group = UserGroup.find(params[:id])
    
    if @user_group.owner == current_user or @user_group.shared
      @entities = @user_group.entities.allowed(current_user, :view).paginate(:page => params[:page], :per_page => 16, :order => 'created_at DESC')
      render :layout => 'wide'
    else
      flash[:error] = I18n.t('errors.access_denied')
      redirect_to denied_path
    end
  end

  def new
    @user_group = UserGroup.new
  end

  def edit
    @user_group = UserGroup.find(params[:id])
  end

  def create
    @user_group = UserGroup.new(params[:user_group])
    @user_group.user_id = current_user.id
    
    if @user_group.save
      respond_to do |format|
        format.html do
          flash[:notice] = I18n.t( 'objects.create_success', :o => @user_group.name )
          redirect_to :action => 'index'
        end
        
        format.json do
          render :nothing => true, :status => 200
        end
      end
    else
      render :action => "new"
    end
  end

  def update
    @user_group = UserGroup.owned_by(current_user).find(params[:id])

    if @user_group.update_attributes(params[:user_group])
      flash[:notice] = I18n.t( 'objects.update_success', :o => @user_group.name )
      redirect_to(@user_group)
    else
      render :action => "edit"
    end
  end

  def destroy
    @user_group = UserGroup.owned_by(current_user).find(params[:id])
    @user_group.destroy
    redirect_to(user_groups_url)
  end
  
  protected
    def generally_authorized?
      action_name == 'shared' || (current_user && current_user != User.guest)
    end
  
end
