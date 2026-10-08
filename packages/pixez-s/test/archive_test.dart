import 'dart:io';
import 'package:pixez_s/config/server_config.dart';
import 'package:pixez_s/db/archive_dao.dart';
import 'package:pixez_s/db/database.dart';
import 'package:pixez_s/service/archive_service.dart';
import 'package:test/test.dart';

void main() {
  group('Archive & Fallback Mirror Tests', () {
    late Directory tempDir;
    late AppDatabase appDb;
    late ArchiveDao archiveDao;
    late ArchiveService archiveService;
    late ServerConfig config;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('pixez_test_');
      config = ServerConfig(dataDir: tempDir.path);
      config.ensureDirectories();

      appDb = AppDatabase.open(config.dbDir);
      archiveDao = ArchiveDao(appDb.db);
      archiveService = ArchiveService(archiveDao: archiveDao, config: config);
    });

    tearDown(() {
      appDb.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('should archive illustration with tags and format as local mirror', () async {
      final sampleIllust = {
        'id': 98765432,
        'title': 'Test Artwork',
        'type': 'illust',
        'caption': 'This is a description',
        'create_date': '2026-05-01T12:00:00+00:00',
        'page_count': 1,
        'user': {
          'id': 112233,
          'name': 'Test Artist',
        },
        'tags': [
          {'name': 'original'},
          {'name': 'vocaloid'},
        ],
        'image_urls': {
          'square_medium': 'https://i.pximg.net/c/360x360_70/custom.jpg',
          'medium': 'https://i.pximg.net/c/540x540_70/custom.jpg',
          'large': 'https://i.pximg.net/c/600x1200_90/custom.jpg',
        },
        'meta_single_page': {
          'original_image_url': 'https://i.pximg.net/img-original/img/custom.jpg',
        },
      };

      // Mock a downloaded local file
      final localFile = File('${config.archiveDir}/illust/98765432/98765432_p0.jpg');
      localFile.parent.createSync(recursive: true);
      localFile.writeAsStringSync('fake-jpeg-data');

      // 1. Archive the work
      final archived = await archiveService.archiveIllustration(
        illustJson: sampleIllust,
        downloadedFilePaths: [localFile.path],
      );

      expect(archived.workId, equals('98765432'));
      expect(archived.title, equals('Test Artwork'));
      expect(archived.tags, containsAll(['original', 'vocaloid']));

      // 2. Query by ID
      final queried = archiveService.getById('98765432');
      expect(queried, isNotNull);
      expect(queried!.userName, equals('Test Artist'));
      expect(queried.localFiles.length, equals(1));

      // 3. Search by tag
      final searchByTag = archiveService.search(tag: 'vocaloid');
      expect(searchByTag.length, equals(1));
      expect(searchByTag.first.workId, equals('98765432'));

      // 4. Test Local Mirror Formatting
      const baseUrl = 'http://localhost:8080';
      final formattedMirror = archiveService.formatAsIllustDetailResponse(queried, baseUrl);

      expect(formattedMirror['_is_local_mirror'], isTrue);
      final illustObj = formattedMirror['illust'] as Map<String, dynamic>;
      expect(illustObj['title'], equals('Test Artwork'));
      expect(illustObj['image_urls']['large'], contains('/api/v1/media/archive/illust/98765432/98765432_p0.jpg'));
    });
  });
}
