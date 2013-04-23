require "spec_helper"

describe "Shared multi-tenant MySQL", components: [:ccng, :mysql] do
  let(:create_app_request) do
    {
      "space_guid" => space_guid,
      "name"       => "mysql_binding_test",
      "instances"  => 1,
      "memory"     => 256
    }
  end

  def bind_service
    instance_guid = provision_mysql_instance("yoursql")
    app_guid = ccng_post("/v2/apps", create_app_request).fetch("metadata").fetch("guid")

    create_binding_request = {
      app_guid: app_guid, service_instance_guid: instance_guid
    }
    ccng_post("/v2/service_bindings", create_binding_request)
  end

  def get_creds(binding_response)
    creds = binding_response.fetch("entity").fetch("credentials")
    "mysql2://#{creds["user"]}:#{creds["password"]}@#{creds["host"]}:#{creds["port"]}/#{creds["name"]}"
  end

  it "can provision a service instance" do
    ccng_get("/v2/spaces/#{space_guid}/service_instances").fetch("total_results").should == 0
    expect {
      provision_mysql_instance("yoursql")
      provision_mysql_instance("oursql")
    }.to change { mysql_root_connection["SHOW DATABASES"].to_a.size }.by(2)
    ccng_get("/v2/spaces/#{space_guid}/service_instances").fetch("total_results").should == 2
  end

  it "can bind a service instance" do
    conn_string = get_creds(bind_service)
    Sequel.connect(conn_string) do |conn|
      expect {
        conn.run("CREATE TABLE ponies(hay INTEGER)")
      }.to change { conn["SHOW TABLES"].to_a.length }.from(0).to(1)
    end
  end

  it "can unbind a service instance" do
    binding_response = bind_service
    ccng_delete("/v2/service_bindings/#{binding_response.fetch("metadata").fetch("guid")}")
    conn_string = get_creds(binding_response)
    expect {
      Sequel.connect(conn_string) do |conn|
        conn.run("CREATE TABLE ponies(hay INTEGER)")
      end
    }.to raise_error(Sequel::DatabaseConnectionError, /Access denied/)
  end

  it "can delete a service instance" do
    service_instance_guid = provision_mysql_instance("oursql")
    ccng_delete("/v2/service_instances/#{service_instance_guid}")

    ccng_get("/v2/spaces/#{space_guid}/service_instances").fetch("total_results").should == 0
  end
end