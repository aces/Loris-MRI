from unittest.mock import Mock, patch

from loris_bids_importer.acquisitions import (
    BidsImportFileStatus,
    import_bids_acquisitions,
)


def test_acquisition_failure_logs_nested_errors_and_continues():
    env = Mock()
    importer = Mock(failed_acquisitions_count=0, ignored_acquisitions_count=0)
    first_info = Mock(name='first', data_type='eeg')
    second_info = Mock(name='second', data_type='eeg')
    failure = ExceptionGroup('Invalid acquisition', [
        ValueError('Missing channel'),
        ExceptionGroup('Invalid electrodes', [ValueError('Missing coordinates')]),
    ])
    import_function = Mock(side_effect=[
        failure,
        Mock(status=BidsImportFileStatus.IGNORE, path='already-imported.eeg'),
    ])

    with (
        patch('loris_bids_importer.acquisitions.log'),
        patch('loris_bids_importer.acquisitions.log_error') as log_error,
    ):
        import_bids_acquisitions(
            env, importer, Mock(), [(object(), first_info), (object(), second_info)], import_function,
        )

    log_error.assert_called_once()
    message = log_error.call_args.args[1]
    assert 'Invalid acquisition' in message
    assert '  Missing channel' in message
    assert 'Invalid electrodes' in message
    assert '    Missing coordinates' in message
    assert message.endswith('Skipping.')
    assert importer.failed_acquisitions_count == 1
    assert importer.ignored_acquisitions_count == 1
    assert import_function.call_count == 2
