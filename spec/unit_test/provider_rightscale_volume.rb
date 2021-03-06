#
# Cookbook Name:: rightscale_volume
# Spec:: provider_rightscale_volume
#
# Copyright (C) 2013 RightScale, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'spec_helper'

describe Chef::Provider::RightscaleVolume do
  let(:provider) do
    provider = Chef::Provider::RightscaleVolume.new(new_resource, run_context)
    provider.stub(:initialize_api_client).and_return(client_stub)
    provider
  end

  let(:new_resource) { Chef::Resource::RightscaleVolume.new('test_volume') }
  let(:current_resource) { Chef::Resource::RightscaleVolume.new('test_volume') }
  let(:events) { Chef::EventDispatch::Dispatcher.new }
  let(:node) do
    node = Chef::Node.new
    node.set['rightscale_volume'] = {}
    node
  end
  let(:run_context) { Chef::RunContext.new(node, {}, events) }

  # Mock objects for the right_api_client
  let(:client_stub) do
    client = double('RightApi::Client', :log => nil)
    client.stub(:get_instance).and_return(instance_stub)
    client
  end

  let(:volume_resource) do
    volume = double('volumes')
    volume.stub(
      :show => volume_stub,
      :href => 'some_href',
      :destroy => nil
    )
    volume
  end

  let(:volume_stub) do
    volume = double('volume')
    volume.stub(
      :name => 'test_volume',
      :size => '1',
      :description => 'test_volume description',
      :resource_uid => 'some_id',
      :status => 'available',
      :href => 'some_href'
    )
    volume
  end

  let(:volume_attachment_resource) do
    attachment = double('volume_attachments')
    attachment.stub(
      :show => volume_attachment_stub,
      :volume => volume_resource,
      :destroy => nil
    )
    attachment
  end

  let(:volume_attachment_stub) do
    attachment = double('volume_attachment')
    attachment.stub(
      :state => 'available',
      :device => 'some_device'
    )
    attachment
  end

  let(:snapshot_resource) do
    snapshot = double('volume_snapshots')
    snapshot.stub(
      :index => [],
      :show => snapshot_stub,
      :destroy => nil
    )
    snapshot
  end

  let(:snapshot_stub) do
    snapshot = double('volume_snapshot')
    snapshot.stub(
      :updated_at => 'some_time',
      :state => 'available',
      :name => 'some_name',
      :resource_uid => 'some_id'
    )
    snapshot
  end

  let(:instance_stub) { double('instance', :links => [], :href => 'some_href') }

  let(:volume_type_stub) do
    volume_type = double('volume_type')
    volume_type.stub(
      :name => 'some_name',
      :href => 'some_href',
      :resource_uid => 'some_id'
    )
    volume_type
  end

  # Returns an array of given object.
  #
  # @param object [Object] the object that should be returned in an array
  # @param n [Integer] the size of the array
  #
  # @return [<Object>Array] the array of objects
  #
  def array_of(object, n = 1)
    Array.new(n) { object }
  end

  describe "#load_current_resource" do
    before(:each) do
      node.set['rightscale_volume']['test_volume'] = {
        'volume_id' => 'some_id',
        :device => 'some_device'
      }
    end

    context "when the volume does not exist in the node" do
      it "should return current_resource" do
        new_resource.name = 'new_test_volume'
        provider.load_current_resource
        provider.current_resource.volume_id.should be_nil
        provider.current_resource.state.should be_nil
        provider.current_resource.size.should == 1
        provider.current_resource.description.should be_nil
        provider.current_resource.device.should be_nil
      end
    end

    context "when the volume exists in the node" do
      context "when the volume exists in the cloud" do
        it "should get volume details from the API" do
          provider.stub(:find_volumes).and_return(array_of(volume_resource))
          provider.load_current_resource

          provider.current_resource.volume_id.should == 'some_id'
          provider.current_resource.state.should_not be_nil
          provider.current_resource.size.should == 1
          provider.current_resource.description.should == 'test_volume description'
          provider.current_resource.device.should == 'some_device'
        end
      end

      context "when the volume does not exist in the cloud" do
        it "should raise an exception" do
          provider.stub(:find_volumes).and_return([])
          expect {
            provider.load_current_resource
          }.to raise_error(RuntimeError)
        end
      end
    end
  end

  # Test all actions supported by the provider
  #
  describe "actions" do

    # Creates a test volume by stubbing out the create_volume method.
    #
    def create_test_volume
      provider.stub(:create_volume).and_return(volume_stub)
      volume_stub.stub(:status).and_return('available')
      run_action(:create)
    end

    # Attaches a test volume by stubbing out the attach_volume method.
    #
    def attach_test_volume
      provider.stub(:device_letter_exclusions => [])
      provider.stub(:get_next_device).and_return('some_device')
      provider.stub(:attach_volume).and_return('/dev/some_device')
      run_action(:attach)
      volume_stub.stub(:status).and_return('in-use')
    end

    # Runs the specified action.
    #
    def run_action(action_sym)
      provider.run_action(action_sym)
      provider.load_current_resource
    end


    before(:each) do
      node.set['rightscale_volume'] = {}

      new_resource.size = volume_stub.size.to_i
      new_resource.description = volume_stub.description

      provider.stub(:find_volumes).and_return(array_of(volume_resource))
      provider.new_resource = new_resource
    end

    describe "#action_create" do
      context "volume does not exist" do
        it "should create the volume" do
          provider.should_receive(:create_volume).and_return(volume_stub)
          run_action(:create)
        end

        context "trying to create a volume with a specific ID" do
          it "should not create the volume" do
            new_resource.volume_id = 'some_id'
            provider.should_not_receive(:create_volume)
            expect {
              run_action(:create)
            }.to raise_error(RuntimeError, "Cannot create a volume with specific ID.")
          end
        end

        context "given a snapshot ID" do
          it "should create a volume from the snapshot" do
            snapshot_id = 'some_snapshot_id'
            new_resource.snapshot_id = snapshot_id
            provider.should_receive(:create_volume).with(
              volume_stub.name,
              volume_stub.size.to_i,
              volume_stub.description,
              snapshot_id,
              {}
            ).and_return(volume_stub)
            run_action(:create)
          end
        end

        context "volume was not successfully created" do
          it "should raise an exception" do
            provider.stub(:create_volume).and_return(nil)

            expect {
              run_action(:create)
            }.to raise_error(RuntimeError)
          end
        end
      end

      context "volume already exists" do
        context "requested volume size same as the one already exists" do
          it "should not create a new volume" do
            create_test_volume
            provider.should_not_receive(:create_volume)
            run_action(:create)
          end
        end

        context "requested volume size is different from the one already exists" do
          it "should raise an exception" do
            create_test_volume
            provider.new_resource.size = 10
            expect {
              run_action(:create)
            }.to raise_error(RuntimeError)
          end
        end
      end
    end

    describe "#action_attach" do
      context "volume to be attached exists and not in use" do
        it "should attach the volume" do
          create_test_volume

          attached_device = '/dev/some_device'
          provider.stub(:device_letter_exclusions => [])
          provider.should_receive(:get_next_device).and_return('some_device')
          provider.should_receive(:attach_volume).and_return(attached_device)

          run_action(:attach)
        end

        context "volume not attached successfully" do
          it "should raise an exception" do
            create_test_volume
            provider.stub(:device_letter_exclusions => [])
            provider.stub(:get_next_device).and_return('some_device')
            provider.stub(:attach_volume).and_return(nil)

            expect {
              run_action(:attach)
            }.to raise_error(RuntimeError)
          end
        end
      end

      context "volume to be attached exists and in use" do
        it "should not attach the volume" do
          create_test_volume
          attach_test_volume

          provider.should_not_receive(:get_next_device)
          run_action(:attach)
        end
      end

      context "volume to be attached does not exist" do
        it "should raise an exception" do
          expect {
            run_action(:attach)
          }.to raise_error(RuntimeError)
        end
      end
    end

    describe "#action_snapshot" do
      context "volume to be snapshotted exists" do
        it "should take a snapshot of the volume" do
          create_test_volume

          provider.should_receive(:create_snapshot).and_return(snapshot_stub)
          run_action(:snapshot)
        end

        context "volume snapshot failed" do
          it "should raise an exception" do
            create_test_volume
            provider.stub(:create_snapshot).and_return(nil)

            expect {
              run_action(:snapshot)
            }.to raise_error(RuntimeError)
          end
        end
      end

      context "volume to be snapshotted does not exist" do
        it "should raise an exception" do
          expect {
            run_action(:snapshot)
          }.to raise_error(RuntimeError)
        end
      end
    end

    describe "#action_detach" do
      context "volume to be detached exists and in use" do
        it "should detach the volume" do
          create_test_volume
          attach_test_volume

          provider.should_receive(:detach_volume).and_return(volume_stub)
          run_action(:detach)
        end
      end

      context "volume to be detached exists and not in use" do
        it "should not detach the volume" do
          create_test_volume

          provider.should_not_receive(:detach_volume)
          run_action(:detach)
        end
      end

      context "volume to be detached does not exist" do
        it "should raise an exception" do
          expect {
            run_action(:detach)
          }.to raise_error(RuntimeError)
        end
      end
    end

    describe "#action_delete" do
      context "volume to be deleted exists and not in use" do
        it "should delete volume" do
          create_test_volume

          provider.should_receive(:delete_volume).and_return(true)
          run_action(:delete)
        end

        context "volume deletion failed" do
          before(:each) do
            create_test_volume
            provider.stub(:delete_volume).and_return(false)
          end

          context "on Rackspace Open Cloud" do
            it "should not raise execption" do
              node.set['cloud']['provider'] = 'rackspace-ng'
              expect {
                run_action(:delete)
              }.to_not raise_error(RuntimeError)
            end
          end

          context "on all other clouds" do
            it "should raise an exception" do
              node.set['cloud']['provider'] = 'some_cloud'
              expect {
                run_action(:delete)
              }.to raise_error(RuntimeError)
            end
          end
        end
      end

      context "volume to be deleted exists and in use" do
        it "should raise an exception" do
          create_test_volume
          attach_test_volume
          expect {
            run_action(:delete)
          }.to raise_error(RuntimeError)
        end
      end

      context "volume to be deleted does not exist" do
        it "should not delete volume" do
          provider.should_not_receive(:delete_volume)
          run_action(:delete)
        end
      end
    end

    describe "#action_cleanup" do
      context "volume for which old snapshots need to be cleaned exists" do
        it "should clean up snapshots" do
          create_test_volume

          provider.should_receive(:cleanup_snapshots).and_return(3)
          run_action(:cleanup)
        end
      end

      context "volume for which old snapshots need to be cleaned does not exist" do
        it "should not clean up snapshots" do
          expect {
            run_action(:cleanup)
          }.to raise_error(RuntimeError)
        end
      end
    end
  end

  # Spec test for the helper methods in the provider
  describe "class methods" do

    before(:each) do
      provider.load_current_resource
    end

    describe "#create_volume" do
      before(:each) do
        volume_resource.stub(:create).and_return(volume_resource)
      end

      context "given the name and size for the volume" do
        context "the cloud provider is not rackspace-ng or cloudstack" do
          it "should create the volume" do
            node.set['cloud']['provider'] = 'some_cloud'
            client_stub.should_receive(:volumes).and_return(volume_resource)
            provider.send(:create_volume, 'name', 1)
          end
        end
      end
    end

    describe "#get_volume_type_href" do

      # Creates a dummy volume type.
      #
      # @param name [String] name of the volume type
      # @param id [String] resource UID of the volume type
      # @param size [String] size of the volume type
      # @param href [String] href of the volume type
      #
      def create_test_volume_type(name, id, size, href)
        volume_type = double('volume_types')
        volume_type.stub(:name => name, :resource_uid => id, :size => size, :href => href)
        volume_type
      end

      context "when the cloud is neither rackspace-ng nor cloudstack" do
        it "should return nil" do
          volume_type = provider.send(:get_volume_type_href, 'some_cloud', 1)
          volume_type.should be_nil
        end
      end

      context "when the cloud is rackspace-ng" do
        before(:each) do
          sata = create_test_volume_type('sata', 'sata', 100, 'sata')
          ssd = create_test_volume_type('ssd', 'ssd', 100, 'ssd')
          volume_type_stub.stub(:index => [sata, ssd])
          client_stub.stub(:volume_types).and_return(volume_type_stub)
        end

        it "should return href of the requested volume type" do
          volume_type = provider.send(:get_volume_type_href, 'rackspace-ng', 100, {:volume_type => 'SATA'})
          volume_type.should == 'sata'

          volume_type = provider.send(:get_volume_type_href, 'rackspace-ng', 100, {:volume_type => 'SSD'})
          volume_type.should == 'ssd'
        end
      end

      context "when the cloud is cloudstack" do
        before(:each) do
          # Create dummy volume types
          volume_type_1 = create_test_volume_type('type_1', 'id_1', '5', 'href_1')
          volume_type_2 = create_test_volume_type('type_2', 'id_2', '10', 'href_2')
          volume_type_stub.stub(:index => [volume_type_1, volume_type_2])
          client_stub.stub(:volume_types).and_return(volume_type_stub)
        end

        context "when a custom volume does not exist" do
          context "when volume type href with size equal to the requested size exists" do
            it "should return volume type href" do
              href = provider.send(:get_volume_type_href, 'cloudstack', 5)
              href.should == 'href_1'
            end
          end

          context "when volume type href with size greater than the requested size exists" do
            it "should return volume type href" do
              href = provider.send(:get_volume_type_href, 'cloudstack', 8)
              href.should == 'href_2'
            end
          end

          context "when no volume type href with size greater than or equal to the requested size exists" do
            it "should return volume type href" do
              expect {
                href = provider.send(:get_volume_type_href, 'cloudstack', 20)
              }.to raise_error(RuntimeError)
            end
          end
        end

        context "when a custom volume type exist" do
          it "should return href of the custom volume type with the requested size" do
            custom_volume_type = create_test_volume_type('custom', 'custom', '0', 'custom')
            volume_type_stub.stub(:index => [custom_volume_type])
            volume_type_href = provider.send(:get_volume_type_href, 'cloudstack', 3)
            volume_type_href.should == 'custom'
          end
        end
      end
    end

    describe "#delete_volume" do
      it "should delete the volume in the cloud" do
        provider.stub(:find_volumes).and_return(array_of(volume_resource))
        volume_resource.should_receive(:destroy)
        status = provider.send(:delete_volume, 'volume_id')
        status.should == true
      end
    end

    describe "#attach_volume" do
      it "should attach the volume to an instance" do
        provider.stub(:find_volumes).and_return(array_of(volume_resource))
        provider.stub(:get_current_devices).and_return(['device_1', 'device_2'])

        node.set[:virtualization][:system] = 'some_hypervisor'
        node.set['cloud']['provider'] = 'some_cloud'
        volume_attachment_resource.stub(:state => 'attached')
        volume_stub.stub(:status => 'in-use')

        client_stub.should_receive(:volume_attachments).and_return(volume_attachment_resource)
        volume_attachment_resource.should_receive(:create).and_return(volume_attachment_resource)
        provider.send(:attach_volume, 'some_id', 'some_device')
      end
    end

    describe "#find_volumes" do
      it "should find volumes based on the given filter" do
        client_stub.should_receive(:volumes).and_return(volume_resource)
        volume_resource.should_receive(:index).and_return(array_of(volume_resource))
        volumes = provider.send(:find_volumes)
        volumes.should be_a_kind_of(Array)
      end
    end

    describe "#attached_devices" do
      it "should return the devices attached to the instance" do
        provider.should_receive(:volume_attachments).and_return(array_of(volume_attachment_resource))
        devices = provider.send(:attached_devices)
        devices.should be_a_kind_of(Array)
      end
    end

    describe "#volume_attachments" do
      it "should return the attached volumes based on the given filter" do
        client_stub.should_receive(:volume_attachments).and_return(volume_attachment_resource)
        volume_attachment_resource.stub(:index).and_return(array_of(volume_attachment_resource))
        attachments = provider.send(:volume_attachments)
        attachments.should be_a_kind_of(Array)
      end
    end

    describe "#detach_volume" do
      it "should detach the volume from the instance" do
        provider.stub(:find_volumes).and_return(array_of(volume_resource))
        client_stub.should_receive(:volume_attachments).and_return(volume_attachment_resource)
        volume_attachment_resource.stub(:index => array_of(volume_attachment_resource))
        volume_attachment_resource.should_receive(:destroy)
        provider.send(:detach_volume, 'volume_id')
      end
    end

    describe "#create_snapshot" do
      it "should create a snapshot of the given volume" do
        provider.stub(:find_volumes).and_return(array_of(volume_resource))
        client_stub.should_receive(:volume_snapshots).and_return(snapshot_resource)
        snapshot_resource.should_receive(:create).and_return(snapshot_resource)
        provider.send(:create_snapshot, 'snapshot_name', 'volume_id')
      end
    end

    describe "#get_snapshots" do
      it "should get all the snapshots of the given volume" do
        provider.stub(:find_volumes).and_return(array_of(volume_resource))
        client_stub.should_receive(:volume_snapshots).and_return(snapshot_resource)
        provider.send(:get_snapshots, 'volume_id')
      end
    end

    describe "#cleanup_snapshots" do
      before(:each) do
        provider.stub(:get_snapshots).and_return(array_of(snapshot_resource))
      end

      context "max_snapshots equal to or more than the number of old available snapshots" do
        it "should not delete any snapshots" do
          num_snapshots_deleted = provider.send(:cleanup_snapshots, 'some_volume_id', 3)
          num_snapshots_deleted.should == 0
        end
      end

      context "max_snapshots lesser than the number of old available snapshots" do
        it "should delete old snapshots exceeding max_snapshots" do
          num_snapshots_deleted = provider.send(:cleanup_snapshots, 'some_volume_id', 0)
          num_snapshots_deleted.should == 1
        end
      end
    end

    describe "#get_current_devices" do
      let(:devices) do
        proc_partitions = [
          'major minor  #blocks  name',
          '',
          '1        0  123456789 xvda',
          '1        1     123456 xvda1',
          '2        0    1234567 dm-0',
          '3        0    1234567 dm-1'
        ]
        IO.stub(:readlines).and_return(proc_partitions)
        provider.send(:get_current_devices)
      end

      it "should return at least one partition" do
        devices.should have_at_least(1).items
      end

      it "should not list LVM partitions" do
        devices.select { |item| item =~ /dm-\d/ }.should be_empty
      end

      it "should return items with '/dev' string prefix" do
        devices.reject { |item| item =~ /^\/dev/ }.should be_empty
      end
    end

    describe "#get_next_device" do
      it "should return the next available device" do
        node.set['cloud']['provider'] = 'some_cloud'

        provider.stub(:get_current_devices).and_return(['/dev/sda', '/dev/sdb'])
        device = provider.send(:get_next_device)
        device.should == '/dev/sdc'

        provider.stub(:get_current_devices).and_return(['/dev/sda', '/dev/sdb'])
        device_exclusions = ('c' .. 'g')
        device = provider.send(:get_next_device, device_exclusions)
        device.should == '/dev/sdh'

        provider.stub(:get_current_devices).and_return(['/dev/sda1', '/dev/sda2', '/dev/sda3'])
        device = provider.send(:get_next_device)
        device.should == '/dev/sda4'
      end

      context "when the partitions in /proc/partitions are of unknown type" do
        it "should raise an error" do
          node.set['cloud']['provider'] = 'some_cloud'
          provider.stub(:get_current_devices).and_return(['/dev/vcs', '/dev/vcs1'])
          expect {
            provider.send(:get_next_device)
          }.to raise_error(RuntimeError, "unknown partition/device name: /dev/vcs")
        end
      end

      context "when the cloud provider is ec2" do
        it "should not return the device as anything between (s|xv|h)da and (s|xv|h)de" do
          node.set['cloud']['provider'] = 'ec2'
          provider.stub(:get_current_devices).and_return(['/dev/sda', '/dev/sdb'])
          device = provider.send(:get_next_device)
          device.should == '/dev/sdf'
        end

        it "should not return the device as anything between xvda and xvde if the instance is of HVM type" do
          node.set['cloud']['provider'] = 'ec2'
          provider.stub(:get_current_devices).and_return(['/dev/hda'])
          device = provider.send(:get_next_device)
          device.should == '/dev/xvdf'
        end
      end
    end

    describe "#device_letter_exclusions" do
      context "when the cloud provider is anything other than cloudstack" do
        it "should return an empty array" do
          node.set['cloud']['provider'] = 'some_cloud'
          provider.send(:device_letter_exclusions).should have(0).items
        end
      end

      context "when the cloud provider is cloudstack" do
        it "should return an array with one element and the element must be 'd'" do
          node.set['cloud']['provider'] = 'cloudstack'
          exclusions = provider.send(:device_letter_exclusions)
          exclusions.should have_at_most(1).items
          exclusions.should include('d')
        end
      end
    end
  end
end
