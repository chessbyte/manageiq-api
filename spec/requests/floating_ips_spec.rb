RSpec.describe 'FloatingIp API' do
  describe 'GET /api/floating_ips' do
    it 'lists all cloud subnets with an appropriate role' do
      floating_ip = FactoryBot.create(:floating_ip)
      api_basic_authorize collection_action_identifier(:floating_ips, :read, :get)
      get(api_floating_ips_url)

      expected = {
        'count'     => 1,
        'subcount'  => 1,
        'name'      => 'floating_ips',
        'resources' => [
          hash_including('href' => api_floating_ip_url(nil, floating_ip))
        ]
      }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(expected)
    end

    it 'forbids access to cloud subnets without an appropriate role' do
      api_basic_authorize

      get(api_floating_ips_url)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET /api/floating_ips/:id' do
    it 'will show a cloud subnet with an appropriate role' do
      floating_ip = FactoryBot.create(:floating_ip)
      api_basic_authorize action_identifier(:floating_ips, :read, :resource_actions, :get)

      get(api_floating_ip_url(nil, floating_ip))

      expect(response.parsed_body).to include('href' => api_floating_ip_url(nil, floating_ip))
      expect(response).to have_http_status(:ok)
    end

    it 'forbids access to a cloud tenant without an appropriate role' do
      floating_ip = FactoryBot.create(:floating_ip)
      api_basic_authorize

      get(api_floating_ip_url(nil, floating_ip))

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'POST /api/floating_ips' do
    it 'forbids access to floating ips without an appropriate role' do
      api_basic_authorize
      post(api_floating_ips_url, :params => gen_request(:query, ""))
      expect(response).to have_http_status(:forbidden)
    end

    it "queues the creating of floating ip" do
      api_basic_authorize collection_action_identifier(:floating_ips, :create)
      provider = FactoryBot.create(:ems_openstack, :name => 'test_provider')
      request = {
        "action"   => "create",
        "resource" => {
          "ems_id" => provider.network_manager.id,
          "name"   => "test_floating_ip"
        }
      }

      post(api_floating_ips_url, :params => request)

      expect_multiple_action_result(1, :success => true, :message => "Creating Floating Ip test_floating_ip for Provider: #{provider.name}", :task => true)
    end

    it "raises error when provider does not support creating of floating ips" do
      api_basic_authorize collection_action_identifier(:floating_ips, :create)
      provider = FactoryBot.create(:ems_amazon, :name => 'test_provider')
      request = {
        "action"   => "create",
        "resource" => {
          "ems_id" => provider.network_manager.id,
          "name"   => "test_floating_ip"
        }
      }

      post(api_floating_ips_url, :params => request)

      expected = {"success" => false, "message" => a_string_including("Create floating ip for Provider #{provider.name}")}
      expect(response.parsed_body["results"].first).to include(expected)
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "POST /api/floating_ips/:id" do
    let(:ems) { FactoryBot.create(:ems_openstack) }
    let(:tenant) { FactoryBot.create(:cloud_tenant_openstack, :ext_management_system => ems) }
    let(:floating_ip) { FactoryBot.create(:floating_ip_openstack, :ext_management_system => ems.network_manager, :cloud_tenant => tenant) }

    it "can queue the updating of a floating ip" do
      api_basic_authorize(action_identifier(:floating_ips, :edit))

      post(api_floating_ip_url(nil, floating_ip), :params => {:action => 'edit', :status => "inactive"})

      expected = {
        'success'   => true,
        'message'   => a_string_including('Updating Floating Ip'),
        'task_href' => a_string_matching(api_tasks_url),
        'task_id'   => a_kind_of(String)
      }
      expect(response.parsed_body).to include(expected)
      expect(response).to have_http_status(:ok)
    end

    it "can't queue the updating of a floating ip unless authorized" do
      api_basic_authorize

      post(api_floating_ip_url(nil, floating_ip), :params => {:action => 'edit', :status => "inactive"})
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "DELETE /api/floating_ips" do
    let(:floating_ip) { FactoryBot.create(:floating_ip_openstack) }

    it "can delete a floating ip" do
      api_basic_authorize(action_identifier(:floating_ips, :delete))

      delete(api_floating_ip_url(nil, floating_ip))

      expect(response).to have_http_status(:no_content)
    end

    it "will not delete a floating ip unless authorized" do
      api_basic_authorize

      delete(api_floating_ip_url(nil, floating_ip))

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/floating_ips with delete action" do
    it "can delete a floating ip" do
      ems = FactoryBot.create(:ems_network)
      floating_ip = FactoryBot.create(:floating_ip_openstack, :ext_management_system => ems)
      api_basic_authorize(action_identifier(:floating_ips, :delete, :resource_actions))

      post(api_floating_ip_url(nil, floating_ip), :params => gen_request(:delete))

      expected = {
        'success'   => true,
        'message'   => a_string_including('Deleting Floating Ip'),
        'task_href' => a_string_matching(api_tasks_url),
        'task_id'   => a_kind_of(String)
      }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(expected)
    end

    it "will not delete a floating ip unless authorized" do
      floating_ip = FactoryBot.create(:floating_ip)
      api_basic_authorize

      post(api_floating_ip_url(nil, floating_ip), :params => {:action => "delete"})

      expect(response).to have_http_status(:forbidden)
    end

    it "can delete multiple floating_ips" do
      ems = FactoryBot.create(:ems_network)
      floating_ip1, floating_ip2 = FactoryBot.create_list(:floating_ip_openstack, 2, :ext_management_system => ems)
      api_basic_authorize(action_identifier(:floating_ips, :delete, :resource_actions))

      post(api_floating_ips_url, :params => {:action => "delete", :resources => [{:id => floating_ip1.id}, {:id => floating_ip2.id}]})

      expect(response).to have_http_status(:ok)
    end

    it "forbids multiple floating ip deletion without an appropriate role" do
      floating_ip1, floating_ip2 = FactoryBot.create_list(:floating_ip, 2)
      api_basic_authorize

      post(api_floating_ips_url, :params => {:action => "delete", :resources => [{:id => floating_ip1.id}, {:id => floating_ip2.id}]})

      expect(response).to have_http_status(:forbidden)
    end

    it "raises an error when delete not supported for floating ip" do
      floating_ip = FactoryBot.create(:floating_ip)
      api_basic_authorize(action_identifier(:floating_ips, :delete, :resource_actions))

      post(api_floating_ip_url(nil, floating_ip), :params => gen_request(:delete))

      expected = {
        'success' => false,
        'message' => a_string_including('Delete for Floating Ip')
      }
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to include(expected)
    end
  end
end
