-- =====================================================
-- DATABASE: HACKATHON MANAGEMENT SYSTEM
-- SQL SERVER VERSION
-- Simplified schema for student project
-- =====================================================
USE master;
GO
IF EXISTS (SELECT name FROM sys.databases WHERE name = 'SEAL_HackathonDB')
    DROP DATABASE SEAL_HackathonDB;
GO
CREATE DATABASE SEAL_HackathonDB
    COLLATE Vietnamese_CI_AS;
GO
USE SEAL_HackathonDB;
GO



-- =====================================================
-- TABLE: users
-- Purpose:
-- Store all system accounts
-- =====================================================

CREATE TABLE users (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),

    full_name NVARCHAR(255) NOT NULL,

    email NVARCHAR(255) UNIQUE NOT NULL,

    password NVARCHAR(255) NOT NULL,

    role NVARCHAR(50),
    -- student / judge / mentor / organizer

    university NVARCHAR(255),

    student_code NVARCHAR(100),

    status NVARCHAR(50),
    -- pending / approved / rejected

    created_at DATETIME DEFAULT GETDATE()
);



-- =====================================================
-- FUNCTION 1: EVENT & ROUND MANAGEMENT
-- =====================================================

-- TABLE: events
-- Purpose:
-- Store hackathon events
CREATE TABLE EVENTS (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),

    name NVARCHAR(255) NOT NULL,

    description NVARCHAR(MAX),

    start_date DATETIME,

    end_date DATETIME,

    status NVARCHAR(50),
    -- upcoming / ongoing / completed

    created_by UNIQUEIDENTIFIER,

    created_at DATETIME DEFAULT GETDATE(),

    FOREIGN KEY (created_by) REFERENCES users(id)
);


-- TABLE: rounds
-- Purpose:
-- Store competition rounds
CREATE TABLE rounds (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),

    event_id UNIQUEIDENTIFIER NOT NULL,

    name NVARCHAR(255),

    round_order INT,

    submission_deadline DATETIME,

    advancement_rule NVARCHAR(255),
    -- Example: "Top 5 teams"

    assigned_judges NVARCHAR(MAX),
    -- Store judge IDs as plain text

    created_at DATETIME DEFAULT GETDATE(),

    FOREIGN KEY (event_id) REFERENCES events(id)
);



-- =====================================================
-- FUNCTION 2: CATEGORY & ROLE MANAGEMENT
-- =====================================================

-- TABLE: categories
-- Purpose:
-- Store competition categories
CREATE TABLE categories (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),

    event_id UNIQUEIDENTIFIER NOT NULL,

    name NVARCHAR(255),

    description NVARCHAR(MAX),

    created_at DATETIME DEFAULT GETDATE(),

    FOREIGN KEY (event_id) REFERENCES events(id)
);


-- TABLE: event_roles
-- Purpose:
-- Assign mentor/judge/organizer roles
CREATE TABLE event_roles (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),

    event_id UNIQUEIDENTIFIER NOT NULL,

    category_id UNIQUEIDENTIFIER,

    user_id UNIQUEIDENTIFIER NOT NULL,

    role_type NVARCHAR(50),
    -- mentor / judge / organizer

    created_at DATETIME DEFAULT GETDATE(),

    FOREIGN KEY (event_id) REFERENCES events(id),

    FOREIGN KEY (category_id) REFERENCES categories(id),

    FOREIGN KEY (user_id) REFERENCES users(id)
);



-- =====================================================
-- FUNCTION 3: TEAM & REGISTRATION MANAGEMENT
-- =====================================================

-- TABLE: teams
-- Purpose:
-- Store competition teams
CREATE TABLE teams (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),

    event_id UNIQUEIDENTIFIER NOT NULL,

    category_id UNIQUEIDENTIFIER,

    name NVARCHAR(255),

    approval_status NVARCHAR(50),
    -- pending / approved / rejected

    registration_status NVARCHAR(50),
    -- active / eliminated

    created_at DATETIME DEFAULT GETDATE(),

    FOREIGN KEY (event_id) REFERENCES events(id),

    FOREIGN KEY (category_id) REFERENCES categories(id)
);


-- TABLE: team_members
-- Purpose:
-- Store team participants
CREATE TABLE team_members (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),

    team_id UNIQUEIDENTIFIER NOT NULL,

    user_id UNIQUEIDENTIFIER NOT NULL,

    is_leader BIT DEFAULT 0,

    joined_at DATETIME DEFAULT GETDATE(),

    FOREIGN KEY (team_id) REFERENCES teams(id),

    FOREIGN KEY (user_id) REFERENCES users(id)
);


-- =====================================================
-- FUNCTION 4: SCORING CRITERIA MANAGEMENT
-- =====================================================

-- TABLE: criteria_templates
-- Purpose:
-- Store reusable scoring templates
CREATE TABLE CriterionTemplate (
    TemplateID    INT           IDENTITY(1,1) PRIMARY KEY,
    CriterionName NVARCHAR(200) NOT NULL,    -- Đã sửa CriteriaName thành CriterionName
    Description   NVARCHAR(MAX) NULL,
    DefaultWeight DECIMAL(5,2)  NOT NULL DEFAULT 1.00,
    MaxScore      DECIMAL(6,2)  NOT NULL DEFAULT 10.00,
    IsActive      BIT           NOT NULL DEFAULT 1,
    CreatedByID   UNIQUEIDENTIFIER NOT NULL REFERENCES users(id),
    CreatedAt     DATETIME2     NOT NULL DEFAULT GETUTCDATE()
);
GO

-- TABLE: event_criteria
-- Purpose:
-- Store scoring criteria for event
CREATE TABLE EventCriteria (
    EventCriterionID INT           IDENTITY(1,1) PRIMARY KEY,
    EventID          UNIQUEIDENTIFIER NOT NULL REFERENCES events(id),
    TemplateID       INT           NULL REFERENCES CriterionTemplate(TemplateID),  -- Cập nhật tên bảng tham chiếu
    CriterionName    NVARCHAR(200) NOT NULL,    -- Đã sửa CriteriaName thành CriterionName
    Description      NVARCHAR(MAX) NULL,
    Weight           DECIMAL(5,2)  NOT NULL DEFAULT 1.00,
    MaxScore         DECIMAL(6,2)  NOT NULL DEFAULT 10.00,
    SortOrder        TINYINT       NOT NULL DEFAULT 0,
    IsActive         BIT           NOT NULL DEFAULT 1,
    CONSTRAINT UQ_EventCriteria_Event_Name UNIQUE (EventID, CriterionName)
);
GO



-- =====================================================
-- FUNCTION 5: SUBMISSION MANAGEMENT
-- =====================================================

-- TABLE: submissions
-- Purpose:
-- Store team submissions
CREATE TABLE submissions (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),

    round_id UNIQUEIDENTIFIER NOT NULL,

    team_id UNIQUEIDENTIFIER NOT NULL,

    submitted_at DATETIME DEFAULT GETDATE(),

    status NVARCHAR(50),
    -- submitted / late / rejected

    FOREIGN KEY (round_id) REFERENCES rounds(id),

    FOREIGN KEY (team_id) REFERENCES teams(id)
);


-- TABLE: submission_assets
-- Purpose:
-- Store submission links
CREATE TABLE submission_assets (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),

    submission_id UNIQUEIDENTIFIER NOT NULL,

    repo_url NVARCHAR(MAX),

    demo_url NVARCHAR(MAX),

    slide_url NVARCHAR(MAX),

    metadata NVARCHAR(MAX),
    -- Store simple text metadata

    FOREIGN KEY (submission_id) REFERENCES submissions(id)
);



-- =====================================================
-- FUNCTION 6: SCORING, RANKING & ADVANCEMENT
-- =====================================================

-- TABLE: scores
-- Purpose:
-- Store scores from judges
CREATE TABLE scores (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),

    submission_id UNIQUEIDENTIFIER NOT NULL,

    judge_id UNIQUEIDENTIFIER NOT NULL,

    -- SỬA Ở ĐÂY: Đổi kiểu dữ liệu từ UNIQUEIDENTIFIER sang INT cho khớp với EventCriteria
    criterion_id INT NOT NULL, 

    score FLOAT,

    comment NVARCHAR(MAX),

    scored_at DATETIME DEFAULT GETDATE(),

    FOREIGN KEY (submission_id) REFERENCES submissions(id),

    FOREIGN KEY (judge_id) REFERENCES users(id),

    -- SỬA Ở ĐÂY: Tham chiếu đúng tên bảng EventCriteria và cột EventCriterionID
    FOREIGN KEY (criterion_id) REFERENCES EventCriteria(EventCriterionID)
);


-- TABLE: rankings
-- Purpose:
-- Store ranking results
CREATE TABLE rankings (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),

    round_id UNIQUEIDENTIFIER NOT NULL,

    team_id UNIQUEIDENTIFIER NOT NULL,

    total_score FLOAT,

    rank_position INT,

    advancement_status NVARCHAR(50),
    -- advanced / eliminated

    eliminated_reason NVARCHAR(MAX),

    FOREIGN KEY (round_id) REFERENCES rounds(id),

    FOREIGN KEY (team_id) REFERENCES teams(id)
);

-- =====================================================
-- TABLE: evaluation_audit_logs
-- Purpose:
-- Store audit logs for all scoring modifications and team/submission eliminations
-- Fully conforms to the system's strict architectural standards
-- =====================================================

CREATE TABLE evaluation_audit_logs (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),

    event_id UNIQUEIDENTIFIER NOT NULL,
    -- To quickly filter logs per hackathon event

    action_type NVARCHAR(50) NOT NULL,

    actor_id UNIQUEIDENTIFIER NOT NULL,

    -- Contextual Foreign Keys (Nullable depending on the action type)
    score_id UNIQUEIDENTIFIER NULL,
    team_id UNIQUEIDENTIFIER NULL,
    submission_id UNIQUEIDENTIFIER NULL,

    old_value NVARCHAR(MAX),

    new_value NVARCHAR(MAX),

    reason NVARCHAR(MAX) NOT NULL,
    -- Mandatory justification for the modification or elimination

    created_at DATETIME DEFAULT GETDATE(),

    FOREIGN KEY (event_id) REFERENCES events(id),
    FOREIGN KEY (actor_id) REFERENCES users(id),
    FOREIGN KEY (score_id) REFERENCES scores(id),
    FOREIGN KEY (team_id) REFERENCES teams(id),
    FOREIGN KEY (submission_id) REFERENCES submissions(id)
);

-- =====================================================
-- FUNCTION 7: REPORTING & AWARD MANAGEMENT
-- =====================================================

-- TABLE: reports
-- Purpose:
-- Store reports & analytics
CREATE TABLE reports (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),

    event_id UNIQUEIDENTIFIER NOT NULL,

    generated_by UNIQUEIDENTIFIER,

    report_type NVARCHAR(50),
    -- csv / excel / analytics

    report_data NVARCHAR(MAX),

    created_at DATETIME DEFAULT GETDATE(),

    FOREIGN KEY (event_id) REFERENCES events(id),

    FOREIGN KEY (generated_by) REFERENCES users(id)
);


-- TABLE: awards
-- Purpose:
-- Store award results
CREATE TABLE awards (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),

    event_id UNIQUEIDENTIFIER NOT NULL,

    team_id UNIQUEIDENTIFIER NOT NULL,

    title NVARCHAR(255),

    description NVARCHAR(MAX),

    announced_at DATETIME,

    FOREIGN KEY (event_id) REFERENCES events(id),

    FOREIGN KEY (team_id) REFERENCES teams(id)
);
CREATE TABLE award_types (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    title NVARCHAR(255) NOT NULL UNIQUE, 
    description NVARCHAR(MAX),
    default_prize_pool NVARCHAR(255), 
    created_at DATETIME DEFAULT GETDATE()
);

ALTER TABLE awards
ADD award_type_id UNIQUEIDENTIFIER NOT NULL;

ALTER TABLE awards
ADD CONSTRAINT FK_awards_award_types 
FOREIGN KEY (award_type_id) REFERENCES award_types(id);

ALTER TABLE awards
ALTER COLUMN announced_at DATETIME2;

ALTER TABLE awards
DROP COLUMN title;