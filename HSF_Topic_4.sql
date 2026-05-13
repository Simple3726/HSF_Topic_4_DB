-- ============================================================
-- SEAL – Software Engineering Agile League
-- Hackathon Management System (MS SQL Server)
-- Version 2.0  |  FPT University HCMC – SE Dept & PDP
-- ============================================================
-- Annual schedule: Spring | Summer | Fall hackathon per year
-- Open to FPT students, external students, and mixed teams
-- Dual purpose: competition platform + inter-rater reliability research
-- ============================================================

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

-- ============================================================
-- SECTION 1 – UNIVERSITIES & USERS
-- ============================================================

-- Universities (FPT + partner universities whose students may compete)
CREATE TABLE Universities (
    UniversityID   INT IDENTITY(1,1) PRIMARY KEY,
    UniversityName NVARCHAR(200) NOT NULL UNIQUE,
    ShortName      NVARCHAR(50)  NULL,
    City           NVARCHAR(100) NULL,
    IsPartner      BIT           NOT NULL DEFAULT 1,   -- 0 = FPT itself
    IsActive       BIT           NOT NULL DEFAULT 1,
    CreatedAt      DATETIME2     NOT NULL DEFAULT GETUTCDATE()
);

-- System roles – kept small; event-level permissions handled separately
CREATE TABLE Roles (
    RoleID      INT IDENTITY(1,1) PRIMARY KEY,
    RoleName    NVARCHAR(60)  NOT NULL UNIQUE,
    Description NVARCHAR(300) NULL
    -- Values: EventCoordinator, Mentor, InternalJudge, GuestJudge, Student
);

CREATE TABLE Users (
    UserID           INT IDENTITY(1,1) PRIMARY KEY,
    FullName         NVARCHAR(150) NOT NULL,
    Email            NVARCHAR(150) NOT NULL UNIQUE,
    PasswordHash     NVARCHAR(512) NOT NULL,
    Phone            NVARCHAR(20)  NULL,
    AvatarURL        NVARCHAR(500) NULL,
    RoleID           INT           NOT NULL REFERENCES Roles(RoleID),
    -- Approval workflow
    IsApproved       BIT           NOT NULL DEFAULT 0,
    ApprovedAt       DATETIME2     NULL,
    ApprovedByUserID INT           NULL,   -- FK set after table created
    -- Temporary accounts created by coordinators for guest judges
    IsTemporary      BIT           NOT NULL DEFAULT 0,
    TemporaryExpiry  DATETIME2     NULL,
    IsActive         BIT           NOT NULL DEFAULT 1,
    CreatedAt        DATETIME2     NOT NULL DEFAULT GETUTCDATE(),
    UpdatedAt        DATETIME2     NULL
);
ALTER TABLE Users ADD CONSTRAINT FK_Users_ApprovedBy FOREIGN KEY (ApprovedByUserID) REFERENCES Users(UserID);

-- Student-specific profile (FPT or external partner university)
CREATE TABLE StudentProfiles (
    StudentProfileID INT IDENTITY(1,1) PRIMARY KEY,
    UserID           INT           NOT NULL UNIQUE REFERENCES Users(UserID),
    StudentCode      NVARCHAR(50)  NOT NULL,
UniversityID     INT           NOT NULL REFERENCES Universities(UniversityID),
    Major            NVARCHAR(150) NULL,
    GraduationYear   SMALLINT      NULL
);

-- Lecturer / judge profile (internal SE / PDP staff or external expert)
CREATE TABLE StaffProfiles (
    StaffProfileID   INT IDENTITY(1,1) PRIMARY KEY,
    UserID           INT           NOT NULL UNIQUE REFERENCES Users(UserID),
    Department       NVARCHAR(150) NULL,   -- e.g. "SE Dept", "PDP", external affiliation
    UniversityID     INT           NULL REFERENCES Universities(UniversityID),
    Specialization   NVARCHAR(200) NULL,
    IsInternal       BIT           NOT NULL DEFAULT 1   -- 0 = guest from outside FPT
);

-- JWT refresh tokens
CREATE TABLE RefreshTokens (
    TokenID   INT IDENTITY(1,1) PRIMARY KEY,
    UserID    INT           NOT NULL REFERENCES Users(UserID),
    Token     NVARCHAR(512) NOT NULL UNIQUE,
    ExpiresAt DATETIME2     NOT NULL,
    RevokedAt DATETIME2     NULL,
    CreatedAt DATETIME2     NOT NULL DEFAULT GETUTCDATE()
);

-- ============================================================
-- SECTION 2 – SCORING CRITERIA TEMPLATES
-- ============================================================

CREATE TABLE CriteriaTemplates (
    TemplateID      INT IDENTITY(1,1) PRIMARY KEY,
    TemplateName    NVARCHAR(150) NOT NULL,
    Description     NVARCHAR(500) NULL,
    IsDefault       BIT           NOT NULL DEFAULT 0,
    CreatedByUserID INT           NULL REFERENCES Users(UserID),
    CreatedAt       DATETIME2     NOT NULL DEFAULT GETUTCDATE(),
    UpdatedAt       DATETIME2     NULL
);

CREATE TABLE TemplateCriteria (
    TemplateCriteriaID INT IDENTITY(1,1) PRIMARY KEY,
    TemplateID         INT           NOT NULL REFERENCES CriteriaTemplates(TemplateID),
    CriteriaName       NVARCHAR(150) NOT NULL,
    Description        NVARCHAR(500) NULL,
    MaxScore           DECIMAL(5,2)  NOT NULL DEFAULT 10.00,
    DefaultWeight      DECIMAL(5,2)  NOT NULL DEFAULT 1.00,
    DisplayOrder       INT           NOT NULL DEFAULT 0,
    CONSTRAINT CK_MaxScore_Template CHECK (MaxScore > 0),
    CONSTRAINT CK_Weight_Template   CHECK (DefaultWeight > 0)
);

-- ============================================================
-- SECTION 3 – HACKATHON EVENTS
-- ============================================================

CREATE TABLE HackathonEvents (
    EventID          INT IDENTITY(1,1) PRIMARY KEY,
    EventName        NVARCHAR(200) NOT NULL,
    -- SEAL season taxonomy: Spring | Summer | Fall + academic year
    Season           NVARCHAR(10)  NOT NULL CHECK (Season IN ('Spring','Summer','Fall')),
    AcademicYear     SMALLINT      NOT NULL,   -- e.g. 2025
    Description      NVARCHAR(MAX) NULL,
    Theme            NVARCHAR(300) NULL,       -- optional competition theme
    Venue            NVARCHAR(300) NULL,
    RegistrationOpen DATETIME2     NULL,
    RegistrationClose DATETIME2   NULL,
    StartDate        DATETIME2     NOT NULL,
EndDate          DATETIME2     NOT NULL,
    Status           NVARCHAR(20)  NOT NULL DEFAULT 'Draft'
                        CHECK (Status IN ('Draft','RegistrationOpen','Ongoing','Scoring','Closed','Archived')),
    -- Default criteria template inherited by this event
    TemplateID       INT           NULL REFERENCES CriteriaTemplates(TemplateID),
    CreatedByUserID  INT           NOT NULL REFERENCES Users(UserID),
    CreatedAt        DATETIME2     NOT NULL DEFAULT GETUTCDATE(),
    UpdatedAt        DATETIME2     NULL,
    CONSTRAINT UQ_Event_Season_Year UNIQUE (Season, AcademicYear)
);

-- Event coordinators: SE Dept and PDP staff assigned to manage an event
CREATE TABLE EventCoordinators (
    EventCoordinatorID INT IDENTITY(1,1) PRIMARY KEY,
    EventID            INT NOT NULL REFERENCES HackathonEvents(EventID),
    UserID             INT NOT NULL REFERENCES Users(UserID),   -- Role = EventCoordinator
    Department         NVARCHAR(50) NOT NULL CHECK (Department IN ('SE','PDP','Other')),
    AssignedAt         DATETIME2    NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT UQ_EventCoordinator UNIQUE (EventID, UserID)
);

-- Per-event scoring criteria (copied/adjusted from template)
CREATE TABLE EventCriteria (
    EventCriteriaID    INT IDENTITY(1,1) PRIMARY KEY,
    EventID            INT           NOT NULL REFERENCES HackathonEvents(EventID),
    TemplateCriteriaID INT           NULL REFERENCES TemplateCriteria(TemplateCriteriaID),
    CriteriaName       NVARCHAR(150) NOT NULL,
    Description        NVARCHAR(500) NULL,
    MaxScore           DECIMAL(5,2)  NOT NULL DEFAULT 10.00,
    Weight             DECIMAL(5,2)  NOT NULL DEFAULT 1.00,
    IsActive           BIT           NOT NULL DEFAULT 1,
    DisplayOrder       INT           NOT NULL DEFAULT 0,
    CONSTRAINT CK_MaxScore_Event CHECK (MaxScore > 0),
    CONSTRAINT CK_Weight_Event   CHECK (Weight > 0)
);

-- ============================================================
-- SECTION 4 – TRACKS (Competition Categories)
-- ============================================================
-- "Track" is the official SEAL term for a competition category / hạng mục

CREATE TABLE Tracks (
    TrackID      INT IDENTITY(1,1) PRIMARY KEY,
    EventID      INT           NOT NULL REFERENCES HackathonEvents(EventID),
    TrackName    NVARCHAR(150) NOT NULL,
    Description  NVARCHAR(500) NULL,
    MaxTeams     INT           NULL,   -- optional cap per track
    IsActive     BIT           NOT NULL DEFAULT 1,
    CreatedAt    DATETIME2     NOT NULL DEFAULT GETUTCDATE()
);

-- Mentor assignment: a lecturer can mentor one track and judge another in the same event
CREATE TABLE TrackMentors (
    TrackMentorID INT IDENTITY(1,1) PRIMARY KEY,
    TrackID       INT NOT NULL REFERENCES Tracks(TrackID),
    UserID        INT NOT NULL REFERENCES Users(UserID),   -- Role = Mentor
    AssignedAt    DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
AssignedByUserID INT NULL REFERENCES Users(UserID),
    CONSTRAINT UQ_TrackMentor UNIQUE (TrackID, UserID)
);

-- ============================================================
-- SECTION 5 – ROUNDS
-- ============================================================

CREATE TABLE Rounds (
    RoundID            INT IDENTITY(1,1) PRIMARY KEY,
    EventID            INT           NOT NULL REFERENCES HackathonEvents(EventID),
    RoundName          NVARCHAR(100) NOT NULL,    -- e.g. "Vòng sơ khảo", "Vòng chung kết"
    RoundOrder         INT           NOT NULL DEFAULT 1,
    SubmissionOpen     DATETIME2     NULL,
    SubmissionDeadline DATETIME2     NULL,
    ScoringDeadline    DATETIME2     NULL,
    Status             NVARCHAR(20)  NOT NULL DEFAULT 'Pending'
                          CHECK (Status IN ('Pending','SubmissionOpen','Scoring','Closed')),
    IsCalibrationRound BIT           NOT NULL DEFAULT 0,   -- RBL: judges score a benchmark set first
    Description        NVARCHAR(500) NULL,
    CreatedAt          DATETIME2     NOT NULL DEFAULT GETUTCDATE()
);

-- Advancement rules: top N teams per track move to the next round
CREATE TABLE AdvancementRules (
    AdvancementRuleID INT IDENTITY(1,1) PRIMARY KEY,
    RoundID           INT NOT NULL REFERENCES Rounds(RoundID),
    TrackID           INT NOT NULL REFERENCES Tracks(TrackID),
    TopN              INT NOT NULL CHECK (TopN > 0),
    CONSTRAINT UQ_AdvancementRule UNIQUE (RoundID, TrackID)
);

-- ============================================================
-- SECTION 6 – JUDGE ASSIGNMENTS
-- ============================================================

CREATE TABLE RoundJudges (
    RoundJudgeID    INT IDENTITY(1,1) PRIMARY KEY,
    RoundID         INT          NOT NULL REFERENCES Rounds(RoundID),
    UserID          INT          NOT NULL REFERENCES Users(UserID),
    -- JudgeType snapshot at assignment time (Internal = SE/PDP staff, Guest = external)
    JudgeType       NVARCHAR(10) NOT NULL CHECK (JudgeType IN ('Internal','Guest')),
    -- NULL = judge all tracks in this round; set to specific track for scoped assignment
    TrackID         INT          NULL REFERENCES Tracks(TrackID),
    AssignedAt      DATETIME2    NOT NULL DEFAULT GETUTCDATE(),
    AssignedByUserID INT         NULL REFERENCES Users(UserID),
    CONSTRAINT UQ_RoundJudge UNIQUE (RoundID, UserID, TrackID)
);

-- ============================================================
-- SECTION 7 – TEAMS & MEMBERS
-- ============================================================

CREATE TABLE Teams (
    TeamID       INT IDENTITY(1,1) PRIMARY KEY,
    TeamName     NVARCHAR(150) NOT NULL,
    TrackID      INT           NOT NULL REFERENCES Tracks(TrackID),
    LeaderUserID INT           NOT NULL REFERENCES Users(UserID),
    -- Composition type derived from members but cached for fast queries
    -- AllFPT | Mixed | AllExternal
CompositionType NVARCHAR(15) NULL CHECK (CompositionType IN ('AllFPT','Mixed','AllExternal')),
    Status       NVARCHAR(20)  NOT NULL DEFAULT 'Pending'
                    CHECK (Status IN ('Pending','Approved','Active','Disqualified','Withdrawn')),
    DisqualifiedAt      DATETIME2     NULL,
    DisqualifiedByUserID INT          NULL REFERENCES Users(UserID),
    DisqualificationReason NVARCHAR(1000) NULL,
    CreatedAt    DATETIME2     NOT NULL DEFAULT GETUTCDATE(),
    UpdatedAt    DATETIME2     NULL
);

CREATE TABLE TeamMembers (
    TeamMemberID INT IDENTITY(1,1) PRIMARY KEY,
    TeamID       INT NOT NULL REFERENCES Teams(TeamID),
    UserID       INT NOT NULL REFERENCES Users(UserID),
    IsLeader     BIT NOT NULL DEFAULT 0,
    JoinedAt     DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT UQ_TeamMember UNIQUE (TeamID, UserID)
);

-- Trigger: enforce 3–5 members per team
GO
CREATE TRIGGER TR_TeamMembers_EnforceSize
ON TeamMembers
AFTER INSERT, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @TeamID INT;

    SELECT DISTINCT @TeamID = TeamID FROM inserted;
    IF @TeamID IS NOT NULL AND (SELECT COUNT(*) FROM TeamMembers WHERE TeamID = @TeamID) > 5
    BEGIN
        RAISERROR (N'Một đội không được có quá 5 thành viên.', 16, 1);
        ROLLBACK TRANSACTION; RETURN;
    END

    SELECT DISTINCT @TeamID = TeamID FROM deleted;
    IF @TeamID IS NOT NULL
       AND EXISTS (SELECT 1 FROM Teams WHERE TeamID = @TeamID AND Status IN ('Active','Approved'))
       AND (SELECT COUNT(*) FROM TeamMembers WHERE TeamID = @TeamID) < 3
    BEGIN
        RAISERROR (N'Một đội cần ít nhất 3 thành viên.', 16, 1);
        ROLLBACK TRANSACTION; RETURN;
    END
END;
GO

-- ============================================================
-- SECTION 8 – SUBMISSIONS
-- ============================================================

CREATE TABLE Submissions (
    SubmissionID          INT IDENTITY(1,1) PRIMARY KEY,
    TeamID                INT           NOT NULL REFERENCES Teams(TeamID),
    RoundID               INT           NOT NULL REFERENCES Rounds(RoundID),
    RepositoryURL         NVARCHAR(500) NULL,
    DemoURL               NVARCHAR(500) NULL,
    ReportURL             NVARCHAR(500) NULL,
    SlideURL              NVARCHAR(500) NULL,
    AdditionalNotes       NVARCHAR(2000) NULL,
    SubmittedAt           DATETIME2     NOT NULL DEFAULT GETUTCDATE(),
    LastUpdatedAt         DATETIME2     NULL,
    Status                NVARCHAR(20)  NOT NULL DEFAULT 'Submitted'
                              CHECK (Status IN ('Submitted','UnderReview','Accepted','Disqualified')),
    DisqualifiedAt        DATETIME2     NULL,
    DisqualifiedByUserID  INT           NULL REFERENCES Users(UserID),
    DisqualificationReason NVARCHAR(1000) NULL,
    CONSTRAINT UQ_TeamRoundSubmission UNIQUE (TeamID, RoundID)
);

-- Optional: GitHub / GitLab metadata fetched via API
CREATE TABLE SubmissionRepoMeta (
MetaID          INT IDENTITY(1,1) PRIMARY KEY,
    SubmissionID    INT           NOT NULL UNIQUE REFERENCES Submissions(SubmissionID),
    Platform        NVARCHAR(20)  NULL CHECK (Platform IN ('GitHub','GitLab','Bitbucket','Other')),
    RepoOwner       NVARCHAR(150) NULL,
    RepoName        NVARCHAR(150) NULL,
    DefaultBranch   NVARCHAR(100) NULL,
    Stars           INT           NULL,
    Forks           INT           NULL,
    OpenIssues      INT           NULL,
    LastCommitSHA   NVARCHAR(100) NULL,
    LastCommitAt    DATETIME2     NULL,
    CommitCount     INT           NULL,
    ContributorCount INT          NULL,
    FetchedAt       DATETIME2     NOT NULL DEFAULT GETUTCDATE()
);

-- ============================================================
-- SECTION 9 – SCORING (granular per-judge per-criterion)
-- ============================================================

CREATE TABLE Scores (
    ScoreID         INT IDENTITY(1,1) PRIMARY KEY,
    SubmissionID    INT           NOT NULL REFERENCES Submissions(SubmissionID),
    JudgeUserID     INT           NOT NULL REFERENCES Users(UserID),
    EventCriteriaID INT           NOT NULL REFERENCES EventCriteria(EventCriteriaID),
    Score           DECIMAL(6,2)  NOT NULL,
    Comment         NVARCHAR(1000) NULL,
    -- For RBL: flag whether this score came from a calibration round
    IsCalibration   BIT           NOT NULL DEFAULT 0,
    ScoredAt        DATETIME2     NOT NULL DEFAULT GETUTCDATE(),
    UpdatedAt       DATETIME2     NULL,
    CONSTRAINT UQ_Score UNIQUE (SubmissionID, JudgeUserID, EventCriteriaID),
    CONSTRAINT CK_ScoreNonNegative CHECK (Score >= 0)
);

-- Materialised aggregate: recomputed by sp_ComputeRoundScores
CREATE TABLE SubmissionAggregateScores (
    AggregateID        INT IDENTITY(1,1) PRIMARY KEY,
    SubmissionID       INT           NOT NULL UNIQUE REFERENCES Submissions(SubmissionID),
    RoundID            INT           NOT NULL REFERENCES Rounds(RoundID),
    WeightedTotalScore DECIMAL(10,4) NOT NULL DEFAULT 0,
    JudgeCount         INT           NOT NULL DEFAULT 0,
    TrackRank          INT           NULL,   -- rank within the same track
    EventRank          INT           NULL,   -- rank across whole event
    ComputedAt         DATETIME2     NOT NULL DEFAULT GETUTCDATE()
);

-- ============================================================
-- SECTION 10 – ADVANCEMENT & ELIMINATION
-- ============================================================

CREATE TABLE RoundAdvancement (
    AdvancementID    INT IDENTITY(1,1) PRIMARY KEY,
    TeamID           INT NOT NULL REFERENCES Teams(TeamID),
    FromRoundID      INT NOT NULL REFERENCES Rounds(RoundID),
    ToRoundID        INT NOT NULL REFERENCES Rounds(RoundID),
    IsEligible       BIT NOT NULL DEFAULT 1,
    ProcessedAt      DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    ProcessedByUserID INT NULL REFERENCES Users(UserID),
CONSTRAINT UQ_RoundAdvancement UNIQUE (TeamID, FromRoundID, ToRoundID)
);

-- ============================================================
-- SECTION 11 – RBL: INTER-RATER RELIABILITY RESEARCH
-- ============================================================

-- Benchmark submissions used in calibration rounds
CREATE TABLE CalibrationSamples (
    SampleID      INT IDENTITY(1,1) PRIMARY KEY,
    RoundID       INT           NOT NULL REFERENCES Rounds(RoundID),
    SampleName    NVARCHAR(150) NOT NULL,
    Description   NVARCHAR(500) NULL,
    RepositoryURL NVARCHAR(500) NULL,
    SlideURL      NVARCHAR(500) NULL,
    ReferenceScore DECIMAL(6,2) NULL,   -- "gold standard" score set by coordinators
    CreatedAt     DATETIME2     NOT NULL DEFAULT GETUTCDATE(),
    CreatedByUserID INT         NULL REFERENCES Users(UserID)
);

-- Judge scores on calibration samples
CREATE TABLE CalibrationScores (
    CalibrationScoreID INT IDENTITY(1,1) PRIMARY KEY,
    SampleID           INT           NOT NULL REFERENCES CalibrationSamples(SampleID),
    JudgeUserID        INT           NOT NULL REFERENCES Users(UserID),
    EventCriteriaID    INT           NOT NULL REFERENCES EventCriteria(EventCriteriaID),
    Score              DECIMAL(6,2)  NOT NULL,
    Comment            NVARCHAR(500) NULL,
    ScoredAt           DATETIME2     NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT UQ_CalibScore UNIQUE (SampleID, JudgeUserID, EventCriteriaID)
);

-- Score variance stats cache per round per criterion (dashboard + CSV export)
CREATE TABLE ScoreVarianceStats (
    StatID          INT IDENTITY(1,1) PRIMARY KEY,
    RoundID         INT           NOT NULL REFERENCES Rounds(RoundID),
    EventCriteriaID INT           NOT NULL REFERENCES EventCriteria(EventCriteriaID),
    MeanScore       DECIMAL(8,4)  NULL,
    Variance        DECIMAL(12,6) NULL,
    StdDev          DECIMAL(8,4)  NULL,
    MinScore        DECIMAL(6,2)  NULL,
    MaxScore        DECIMAL(6,2)  NULL,
    JudgeCount      INT           NULL,
    ComputedAt      DATETIME2     NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT UQ_VarianceStat UNIQUE (RoundID, EventCriteriaID)
);

-- ============================================================
-- SECTION 12 – PRIZES & AWARDS
-- ============================================================

CREATE TABLE PrizeTypes (
    PrizeTypeID   INT IDENTITY(1,1) PRIMARY KEY,
    PrizeName     NVARCHAR(100) NOT NULL,   -- "Giải Nhất", "Best Innovation", etc.
    Description   NVARCHAR(300) NULL,
    DisplayOrder  INT           NOT NULL DEFAULT 0
);

CREATE TABLE Prizes (
    PrizeID          INT IDENTITY(1,1) PRIMARY KEY,
    EventID          INT NOT NULL REFERENCES HackathonEvents(EventID),
    TrackID          INT NULL REFERENCES Tracks(TrackID),  -- NULL = overall event prize
    PrizeTypeID      INT NOT NULL REFERENCES PrizeTypes(PrizeTypeID),
    TeamID           INT NULL REFERENCES Teams(TeamID),    -- NULL until awarded
AwardedAt        DATETIME2 NULL,
    AwardedByUserID  INT NULL REFERENCES Users(UserID),
    CashValue        DECIMAL(12,2) NULL,
    Notes            NVARCHAR(500) NULL
);

-- ============================================================
-- SECTION 13 – COMMUNICATION
-- ============================================================

-- System announcements: coordinator → all participants / specific event
CREATE TABLE Announcements (
    AnnouncementID  INT IDENTITY(1,1) PRIMARY KEY,
    EventID         INT           NULL REFERENCES HackathonEvents(EventID),  -- NULL = platform-wide
    Title           NVARCHAR(200) NOT NULL,
    Body            NVARCHAR(MAX) NOT NULL,
    Audience        NVARCHAR(20)  NOT NULL DEFAULT 'All'
                        CHECK (Audience IN ('All','Students','Judges','Mentors','Coordinators')),
    IsPinned        BIT           NOT NULL DEFAULT 0,
    PublishedAt     DATETIME2     NULL,   -- NULL = draft
    CreatedByUserID INT           NOT NULL REFERENCES Users(UserID),
    CreatedAt       DATETIME2     NOT NULL DEFAULT GETUTCDATE()
);

-- Per-user notification inbox (generated from announcements or system events)
CREATE TABLE Notifications (
    NotificationID  INT IDENTITY(1,1) PRIMARY KEY,
    UserID          INT           NOT NULL REFERENCES Users(UserID),
    AnnouncementID  INT           NULL REFERENCES Announcements(AnnouncementID),
    Title           NVARCHAR(200) NOT NULL,
    Body            NVARCHAR(MAX) NOT NULL,
    NotifType       NVARCHAR(30)  NOT NULL DEFAULT 'Info'
                        CHECK (NotifType IN ('Info','Scoring','Submission','Advancement','Prize','Warning')),
    IsRead          BIT           NOT NULL DEFAULT 0,
    ReadAt          DATETIME2     NULL,
    CreatedAt       DATETIME2     NOT NULL DEFAULT GETUTCDATE()
);

-- ============================================================
-- SECTION 14 – AUDIT LOG
-- ============================================================
-- Covers all scoring actions, disqualifications, and coordinator decisions

CREATE TABLE AuditLogs (
    AuditLogID  BIGINT IDENTITY(1,1) PRIMARY KEY,
    ActorUserID INT            NULL REFERENCES Users(UserID),
    -- Structured action codes, e.g. Score.Create, Score.Update, Team.Disqualify
    Action      NVARCHAR(100)  NOT NULL,
    EntityType  NVARCHAR(100)  NOT NULL,
    EntityID    INT            NULL,
    OldValue    NVARCHAR(MAX)  NULL,   -- JSON snapshot before change
    NewValue    NVARCHAR(MAX)  NULL,   -- JSON snapshot after change
    Reason      NVARCHAR(500)  NULL,   -- free-text reason (required for Disqualify actions)
    IPAddress   NVARCHAR(50)   NULL,
    UserAgent   NVARCHAR(300)  NULL,
    CreatedAt   DATETIME2      NOT NULL DEFAULT GETUTCDATE()
);

-- ============================================================
-- SECTION 15 – INDEXES
-- ============================================================

-- Users
CREATE INDEX IX_Users_Email      ON Users(Email);
CREATE INDEX IX_Users_RoleID     ON Users(RoleID);
CREATE INDEX IX_Users_IsApproved ON Users(IsApproved);

-- Events
CREATE INDEX IX_Events_Status    ON HackathonEvents(Status);
CREATE INDEX IX_Events_Season    ON HackathonEvents(Season, AcademicYear);

-- Tracks & Rounds
CREATE INDEX IX_Tracks_EventID   ON Tracks(EventID);
CREATE INDEX IX_Rounds_EventID   ON Rounds(EventID);
CREATE INDEX IX_Rounds_Status    ON Rounds(Status);

-- Criteria
CREATE INDEX IX_EventCriteria_Event ON EventCriteria(EventID);

-- Teams & Members
CREATE INDEX IX_Teams_TrackID    ON Teams(TrackID);
CREATE INDEX IX_Teams_Status     ON Teams(Status);
CREATE INDEX IX_TeamMembers_User ON TeamMembers(UserID);

-- Submissions
CREATE INDEX IX_Submissions_Team   ON Submissions(TeamID);
CREATE INDEX IX_Submissions_Round  ON Submissions(RoundID);
CREATE INDEX IX_Submissions_Status ON Submissions(Status);

-- Scores (critical path for inter-rater research)
CREATE INDEX IX_Scores_Submission ON Scores(SubmissionID);
CREATE INDEX IX_Scores_Judge      ON Scores(JudgeUserID);
CREATE INDEX IX_Scores_Criteria   ON Scores(EventCriteriaID);
CREATE INDEX IX_Scores_Calib      ON Scores(IsCalibration);

-- RBL
CREATE INDEX IX_CalibScores_Sample ON CalibrationScores(SampleID);
CREATE INDEX IX_CalibScores_Judge  ON CalibrationScores(JudgeUserID);

-- Audit
CREATE INDEX IX_Audit_Actor   ON AuditLogs(ActorUserID);
CREATE INDEX IX_Audit_Entity  ON AuditLogs(EntityType, EntityID);
CREATE INDEX IX_Audit_Created ON AuditLogs(CreatedAt DESC);

-- ============================================================
-- SECTION 16 – SEED DATA
-- ============================================================

-- Universities
INSERT INTO Universities (UniversityName, ShortName, City, IsPartner) VALUES
    (N'Trường Đại học FPT TP.HCM',       N'FPT HCM',  N'Hồ Chí Minh', 0),
    (N'Đại học Bách Khoa TP.HCM',         N'BKU',      N'Hồ Chí Minh', 1),
    (N'Đại học Khoa học Tự nhiên TP.HCM', N'HCMUS',    N'Hồ Chí Minh', 1),
    (N'Đại học Công nghệ Thông tin',       N'UIT',      N'Hồ Chí Minh', 1),
    (N'Đại học Sư phạm Kỹ thuật TP.HCM',  N'HCMUTE',   N'Hồ Chí Minh', 1);

-- Roles
INSERT INTO Roles (RoleName, Description) VALUES
    ('EventCoordinator', N'Ban tổ chức – Khoa SE và PDP, toàn quyền quản lý sự kiện'),
    ('Mentor',           N'Giảng viên hướng dẫn – được phân công theo Track'),
    ('InternalJudge',    N'Giám khảo nội bộ – giảng viên SE / PDP'),
    ('GuestJudge',       N'Giám khảo khách mời – tài khoản tạm thời, chỉ chấm điểm'),
    ('Student',          N'Thí sinh – thành viên hoặc trưởng nhóm đội thi');

-- Default scoring criteria template
INSERT INTO CriteriaTemplates (TemplateName, Description, IsDefault) VALUES
    (N'SEAL Default Criteria', N'Mẫu tiêu chí chấm điểm mặc định dùng chung cho các kỳ SEAL', 1);

DECLARE @TplID INT = SCOPE_IDENTITY();
INSERT INTO TemplateCriteria (TemplateID, CriteriaName, Description, MaxScore, DefaultWeight, DisplayOrder) VALUES
    (@TplID, N'Innovation & Creativity',    N'Tính sáng tạo, đột phá và tư duy mới trong giải pháp',          10, 1.5, 1),
    (@TplID, N'Technical Quality',          N'Chất lượng kỹ thuật, kiến trúc hệ thống và code quality',        10, 1.5, 2),
    (@TplID, N'Problem-Solution Fit',       N'Mức độ phù hợp của giải pháp với bài toán thực tế',              10, 1.5, 3),
    (@TplID, N'Presentation & Demo',        N'Chất lượng thuyết trình, kỹ năng trình bày và demo sản phẩm',    10, 1.0, 4),
    (@TplID, N'Teamwork & Collaboration',   N'Phân công công việc, phối hợp và đóng góp của các thành viên',   10, 0.5, 5);

-- Prize types
INSERT INTO PrizeTypes (PrizeName, DisplayOrder) VALUES
    (N'Giải Nhất',        1),
    (N'Giải Nhì',         2),
    (N'Giải Ba',          3),
    (N'Giải Khuyến Khích',4),
    (N'Best Innovation',  5),
    (N'Best Presentation',6);

-- ============================================================
-- SECTION 17 – VIEWS
-- ============================================================
GO

-- Weighted score per judge per submission (RBL: never aggregated away)
CREATE VIEW vw_JudgeSubmissionScore AS
SELECT
    s.SubmissionID,
    s.JudgeUserID,
    u.FullName        AS JudgeName,
    sub.TeamID,
    sub.RoundID,
    t.TrackID,
    ec.EventCriteriaID,
    ec.CriteriaName,
    s.Score,
    ec.Weight,
    s.Score * ec.Weight          AS WeightedScore,
    s.IsCalibration,
    s.ScoredAt
FROM Scores s
JOIN Users u            ON u.UserID           = s.JudgeUserID
JOIN EventCriteria ec   ON ec.EventCriteriaID = s.EventCriteriaID
JOIN Submissions sub    ON sub.SubmissionID   = s.SubmissionID
JOIN Teams t            ON t.TeamID           = sub.TeamID;
GO

-- Average weighted score across all judges per submission
CREATE VIEW vw_SubmissionAvgScore AS
SELECT
    SubmissionID,
    TeamID,
    RoundID,
    TrackID,
    SUM(WeightedScore) / NULLIF(SUM(Weight), 0) AS AvgWeightedScore,
    COUNT(DISTINCT JudgeUserID)                  AS JudgeCount
FROM vw_JudgeSubmissionScore
WHERE IsCalibration = 0
GROUP BY SubmissionID, TeamID, RoundID, TrackID;
GO

-- Ranking per track per round AND event-wide
CREATE VIEW vw_Rankings AS
SELECT
    SubmissionID,
    TeamID,
    RoundID,
    TrackID,
    AvgWeightedScore,
    JudgeCount,
    RANK() OVER (PARTITION BY RoundID, TrackID ORDER BY AvgWeightedScore DESC) AS TrackRank,
    RANK() OVER (PARTITION BY RoundID          ORDER BY AvgWeightedScore DESC) AS EventRank
FROM vw_SubmissionAvgScore;
GO

-- Score distribution per criterion per round (RBL dashboard)
CREATE VIEW vw_ScoreDistribution AS
SELECT
    sub.RoundID,
    s.EventCriteriaID,
    ec.CriteriaName,
    s.JudgeUserID,
    COUNT(*)              AS ScoreCount,
    AVG(s.Score)          AS MeanScore,
    VAR(s.Score)          AS Variance,
    STDEV(s.Score)        AS StdDev,
MIN(s.Score)          AS MinScore,
    MAX(s.Score)          AS MaxScore
FROM Scores s
JOIN Submissions sub    ON sub.SubmissionID   = s.SubmissionID
JOIN EventCriteria ec   ON ec.EventCriteriaID = s.EventCriteriaID
WHERE s.IsCalibration = 0
GROUP BY sub.RoundID, s.EventCriteriaID, ec.CriteriaName, s.JudgeUserID;
GO

-- Anonymised dataset for inter-rater reliability export (CSV)
-- Team/judge names replaced with pseudonymous IDs for research
CREATE VIEW vw_AnonymisedScores AS
SELECT
    sub.RoundID,
    t.TrackID,
    'T' + RIGHT('0000' + CAST(sub.TeamID AS NVARCHAR), 4)   AS AnonymTeamID,
    'J' + RIGHT('0000' + CAST(s.JudgeUserID AS NVARCHAR), 4) AS AnonymJudgeID,
    ec.CriteriaName,
    s.Score,
    ec.Weight,
    s.ScoredAt
FROM Scores s
JOIN Submissions sub  ON sub.SubmissionID   = s.SubmissionID
JOIN Teams t          ON t.TeamID           = sub.TeamID
JOIN EventCriteria ec ON ec.EventCriteriaID = s.EventCriteriaID
WHERE s.IsCalibration = 0;
GO

-- ============================================================
-- SECTION 18 – STORED PROCEDURES
-- ============================================================

-- SP: Inherit criteria from template when creating/opening an event
CREATE PROCEDURE sp_InheritCriteriaFromTemplate
    @EventID   INT,
    @TemplateID INT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO EventCriteria
        (EventID, TemplateCriteriaID, CriteriaName, Description, MaxScore, Weight, DisplayOrder)
    SELECT
        @EventID,
        tc.TemplateCriteriaID,
        tc.CriteriaName,
        tc.Description,
        tc.MaxScore,
        tc.DefaultWeight,
        tc.DisplayOrder
    FROM TemplateCriteria tc
    WHERE tc.TemplateID = @TemplateID
      AND NOT EXISTS (
          SELECT 1 FROM EventCriteria ec
          WHERE ec.EventID = @EventID AND ec.TemplateCriteriaID = tc.TemplateCriteriaID
      );
END;
GO

-- SP: Compute and persist aggregate scores for a round
CREATE PROCEDURE sp_ComputeRoundScores
    @RoundID INT
AS
BEGIN
    SET NOCOUNT ON;

    MERGE SubmissionAggregateScores AS tgt
    USING (
        SELECT SubmissionID, RoundID, AvgWeightedScore, JudgeCount, TrackRank, EventRank
        FROM vw_Rankings
        WHERE RoundID = @RoundID
    ) AS src ON tgt.SubmissionID = src.SubmissionID
    WHEN MATCHED THEN UPDATE SET
        WeightedTotalScore = src.AvgWeightedScore,
        JudgeCount         = src.JudgeCount,
        TrackRank          = src.TrackRank,
        EventRank          = src.EventRank,
        ComputedAt         = GETUTCDATE()
    WHEN NOT MATCHED THEN INSERT
        (SubmissionID, RoundID, WeightedTotalScore, JudgeCount, TrackRank, EventRank, ComputedAt)
    VALUES
        (src.SubmissionID, src.RoundID, src.AvgWeightedScore, src.JudgeCount,
         src.TrackRank, src.EventRank, GETUTCDATE());
END;
GO

-- SP: Advance top-N teams per track to the next round
CREATE PROCEDURE sp_ProcessAdvancement
    @FromRoundID    INT,
    @ToRoundID      INT,
    @ProcessedByUID INT
AS
BEGIN
    SET NOCOUNT ON;
INSERT INTO RoundAdvancement (TeamID, FromRoundID, ToRoundID, IsEligible, ProcessedByUserID)
    SELECT
        t.TeamID,
        @FromRoundID,
        @ToRoundID,
        1,
        @ProcessedByUID
    FROM SubmissionAggregateScores sas
    JOIN Submissions sub ON sub.SubmissionID = sas.SubmissionID AND sub.Status != 'Disqualified'
    JOIN Teams t         ON t.TeamID = sub.TeamID AND t.Status NOT IN ('Disqualified','Withdrawn')
    JOIN AdvancementRules ar ON ar.RoundID = @FromRoundID AND ar.TrackID = t.TrackID
    WHERE sas.RoundID = @FromRoundID
      AND sas.TrackRank <= ar.TopN
      AND NOT EXISTS (
          SELECT 1 FROM RoundAdvancement ra
          WHERE ra.TeamID = t.TeamID AND ra.FromRoundID = @FromRoundID AND ra.ToRoundID = @ToRoundID
      );
END;
GO

-- SP: Disqualify a submission (coordinator action with mandatory reason)
CREATE PROCEDURE sp_DisqualifySubmission
    @SubmissionID INT,
    @ActorUserID  INT,
    @Reason       NVARCHAR(1000)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE Submissions SET
        Status                 = 'Disqualified',
        DisqualifiedAt         = GETUTCDATE(),
        DisqualifiedByUserID   = @ActorUserID,
        DisqualificationReason = @Reason
    WHERE SubmissionID = @SubmissionID;

    INSERT INTO AuditLogs (ActorUserID, Action, EntityType, EntityID, NewValue, Reason)
    VALUES (@ActorUserID, 'Submission.Disqualify', 'Submissions', @SubmissionID,
            N'{"Status":"Disqualified"}', @Reason);
END;
GO

-- SP: Disqualify a team (coordinator action)
CREATE PROCEDURE sp_DisqualifyTeam
    @TeamID      INT,
    @ActorUserID INT,
    @Reason      NVARCHAR(1000)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE Teams SET
        Status                 = 'Disqualified',
        DisqualifiedAt         = GETUTCDATE(),
        DisqualifiedByUserID   = @ActorUserID,
        DisqualificationReason = @Reason,
        UpdatedAt              = GETUTCDATE()
    WHERE TeamID = @TeamID;

    -- Also disqualify any open submissions for this team
    UPDATE Submissions SET
        Status                 = 'Disqualified',
        DisqualifiedAt         = GETUTCDATE(),
        DisqualifiedByUserID   = @ActorUserID,
        DisqualificationReason = N'Team disqualified: ' + @Reason
    WHERE TeamID = @TeamID AND Status NOT IN ('Disqualified');

    INSERT INTO AuditLogs (ActorUserID, Action, EntityType, EntityID, NewValue, Reason)
    VALUES (@ActorUserID, 'Team.Disqualify', 'Teams', @TeamID,
            N'{"Status":"Disqualified"}', @Reason);
END;
GO

-- SP: Refresh score variance stats (RBL dashboard)
CREATE PROCEDURE sp_RefreshVarianceStats
    @RoundID INT
AS
BEGIN
    SET NOCOUNT ON;

    MERGE ScoreVarianceStats AS tgt
    USING (
        SELECT
            sub.RoundID,
            s.EventCriteriaID,
            AVG(s.Score)              AS MeanScore,
            VAR(s.Score)              AS Variance,
            STDEV(s.Score)            AS StdDev,
            MIN(s.Score)              AS MinScore,
MAX(s.Score)              AS MaxScore,
            COUNT(DISTINCT s.JudgeUserID) AS JudgeCount
        FROM Scores s
        JOIN Submissions sub ON sub.SubmissionID = s.SubmissionID
        WHERE sub.RoundID = @RoundID AND s.IsCalibration = 0
        GROUP BY sub.RoundID, s.EventCriteriaID
    ) AS src ON tgt.RoundID = src.RoundID AND tgt.EventCriteriaID = src.EventCriteriaID
    WHEN MATCHED THEN UPDATE SET
        MeanScore  = src.MeanScore,  Variance   = src.Variance,
        StdDev     = src.StdDev,     MinScore   = src.MinScore,
        MaxScore   = src.MaxScore,   JudgeCount = src.JudgeCount,
        ComputedAt = GETUTCDATE()
    WHEN NOT MATCHED THEN INSERT
        (RoundID, EventCriteriaID, MeanScore, Variance, StdDev, MinScore, MaxScore, JudgeCount, ComputedAt)
    VALUES
        (src.RoundID, src.EventCriteriaID, src.MeanScore, src.Variance,
         src.StdDev, src.MinScore, src.MaxScore, src.JudgeCount, GETUTCDATE());
END;
GO

-- SP: Approve a user account (coordinator action)
CREATE PROCEDURE sp_ApproveUser
    @TargetUserID  INT,
    @ApprovedByUID INT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE Users SET
        IsApproved       = 1,
        ApprovedAt       = GETUTCDATE(),
        ApprovedByUserID = @ApprovedByUID
    WHERE UserID = @TargetUserID AND IsApproved = 0;

    INSERT INTO AuditLogs (ActorUserID, Action, EntityType, EntityID, NewValue)
    VALUES (@ApprovedByUID, 'User.Approve', 'Users', @TargetUserID, N'{"IsApproved":true}');
END;
GO

PRINT N'SEAL_HackathonDB v2.0 schema created successfully.';
PRINT N'Spring | Summer | Fall  –  FPT University HCMC  –  SE Dept & PDP';
