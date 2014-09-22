require File.expand_path(File.dirname(__FILE__) + '/../../../../../spec/spec_helper')
require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe Analytics::Department do

  before :each do
    @account = Account.default
    @account.sub_accounts.create!(name: "Some department")
    account_admin_user

    @acct_statistics = Analytics::Department.new(@user, @account, @account.default_enrollment_term, "current")
  end

  describe "account level statistics" do
    it "should return number of subaccounts" do
      @acct_statistics.statistics[:subaccounts].should == 1
      @acct_statistics.statistics_by_subaccount.size.should == 2
    end

    it "should return the number of courses, across all subaccounts" do
      course(account: @account, active_course: true)
      course(account: @account.sub_accounts.first, active_course: true)
      @acct_statistics.statistics[:courses].should == 2
    end

    it "should return the number of courses, grouped by subaccount" do
      course(account: @account, active_course: true)
      course(account: @account.sub_accounts.first, active_course: true)
      @acct_statistics.statistics_by_subaccount.each { |hsh| hsh[:courses].should == 1 }
    end

    it "should return the number of teachers and students, across all subaccounts" do
      c1 = course(account: @account, active_all: true)
      c2 = course(account: @account.sub_accounts.first, active_all: true)
      student_in_course(course: c1, active_all: true)
      student_in_course(course: c2, active_all: true)
      hsh = @acct_statistics.statistics
      hsh[:teachers].should == 2
      hsh[:students].should == 2
    end

    it "should return the number of teachers and students, grouped by subaccount" do
      c1 = course(account: @account, active_all: true)
      c2 = course(account: @account.sub_accounts.first, active_all: true)
      student_in_course(course: c1, active_all: true)
      student_in_course(course: c2, active_all: true)
      lst = @acct_statistics.statistics_by_subaccount
      lst.each{ |hsh| hsh[:teachers].should == 1 }
      lst.each{ |hsh| hsh[:students].should == 1 }
    end
  end

  context "#calculate_and_clamp_dates" do
    ## Use Case Grid
    #
    # start_at | end_at     | result                    | comments
    # -------- | ---------- | ------------------------- | --------
    # ≤ end_at | ≤ now      | [start_at, end_at]        | nominal past term
    # ≤ now    | > now      | [start_at, now]           | nominal ongoing term
    # > now    | ≥ start_at | [now, now]                | nominal future term
    # ≤ now    | < start_at | [start_at, start_at]      | past or current term with dates out-of-order
    # > now    | < start_at | [now, now]                | future term with dates out-of-order
    # ≤ now    | none       | [start_at, now]           | ongoing term with indefinite end
    # > now    | none       | [now, now]                | future term with indefinite end
    # none     | ≤ now      | [end_at - 1.year, end_at] | past term with indefinite start
    # none     | > now      | [now - 1.year, now]       | ongoing term with indefinite start
    # none     | none       | [now - 1.year, now]       | ongoing term with indefinite start or end

    let!(:now){ Time.zone.now }

    before do
      @acct_statistics.stubs(:slaved).returns(nil)
    end

    def check_clamps(start_at, end_at, expected_start_at = nil, expected_end_at = nil)
      expected_start_at ||= start_at
      expected_end_at ||= end_at

      Timecop.freeze(now) do
        start_at, end_at = @acct_statistics.send(:calculate_and_clamp_dates, start_at, end_at, nil)

        start_at.should == expected_start_at
        end_at.should == expected_end_at
      end
    end

    it "start_at ≤ end_at | end_at ≤ now" do
      check_clamps(6.months.ago, 3.months.ago)
    end

    it "start_at ≤ now | end_at > now" do
      start_at = 3.months.ago
      end_at = 3.months.from_now

      check_clamps(start_at, end_at, start_at, now)
      check_clamps(now, end_at, now, now)
    end

    it "start_at > now | end_at ≥ start_at" do
      start_at = 3.months.from_now
      end_at = 6.months.from_now

      check_clamps(start_at, end_at, now, now)
      check_clamps(start_at, start_at, now, now)
    end

    it "start_at ≤ now | end_at < start_at" do
      start_at = 3.months.ago
      end_at = 6.months.ago

      check_clamps(start_at, end_at, start_at, start_at)
      check_clamps(now, end_at, now, now)
    end

    it "start_at > now | end_at < start_at" do
      check_clamps(6.months.from_now, 3.months.from_now, now, now)
    end

    it "start_at ≤ now | end_at = nil" do
      check_clamps(3.months.ago, nil, nil, now)
      check_clamps(now, nil, now, now)
    end

    it "start_at > now | end_at = nil" do
      check_clamps(3.months.from_now, nil, now, now)
    end

    it "start_at = nil | end_at ≤ now" do
      end_at = 3.months.ago
      check_clamps(nil, end_at, end_at - 1.year)
      check_clamps(nil, now, now - 1.year, now)
    end

    it "start_at = nil | end_at > now" do
      check_clamps(nil, 3.months.from_now, now - 1.year, now)
    end

    it "start_at = nil | end_at = nil" do
      check_clamps(nil, nil, now - 1.year, now)
    end
  end
end