-- Add the Brainstorm project to the imaging test data for the MEG CTF integration test.
-- TODO: Upstream Brainstorm and MEG in Raisinbread once MEG is merged and then delete this file.

INSERT INTO `Project` (`Name`, `Alias`, `recruitmentTarget`, `showSummaryOnLogin`)
VALUES ('Brainstorm', 'BS', 0, 0);
SET @brainstorm_project_id := LAST_INSERT_ID();

INSERT INTO `project_cohort_rel` (`ProjectID`, `CohortID`)
VALUES (@brainstorm_project_id, 1);

INSERT INTO `candidate` (
    `CandID`,
    `PSCID`,
    `Sex`,
    `RegistrationCenterID`,
    `RegistrationProjectID`,
    `Active`,
    `Date_active`,
    `UserID`,
    `Date_registered`,
    `Entity_type`
)
VALUES (
    900001,
    'BS0001',
    'Male',
    1,
    @brainstorm_project_id,
    'Y',
    '2026-01-01',
    'integration-test',
    '2026-01-01',
    'Human'
);
SET @brainstorm_candidate_id := LAST_INSERT_ID();

INSERT INTO `session` (
    `CandidateID`,
    `CenterID`,
    `ProjectID`,
    `VisitNo`,
    `Visit_label`,
    `CohortID`,
    `Active`,
    `Date_active`,
    `UserID`,
    `Date_registered`
)
VALUES (
    @brainstorm_candidate_id,
    1,
    @brainstorm_project_id,
    1,
    'V1',
    1,
    'Y',
    '2026-01-01',
    'integration-test',
    '2026-01-01'
);
