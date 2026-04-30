import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:googleapis/tasks/v1.dart' as tasks;
import 'package:calendar_agent_app/services/task_service.dart';

class MockTasksApi extends Mock implements tasks.TasksApi {}
class MockTasksResource extends Mock implements tasks.TasksResource {}
class MockTask extends Mock implements tasks.Task {}
class TaskFake extends Fake implements tasks.Task {}

void main() {
  setUpAll(() {
    registerFallbackValue(TaskFake());
  });

  late TaskService taskService;
  late MockTasksApi mockTasksApi;
  late MockTasksResource mockTasksResource;

  setUp(() {
    mockTasksApi = MockTasksApi();
    mockTasksResource = MockTasksResource();
    taskService = TaskService(mockTasksApi);

    when(() => mockTasksApi.tasks).thenReturn(mockTasksResource);
  });

  group('TaskService - listTasks', () {
    test('should return formatted string when tasks exist', () async {
      final task1 = tasks.Task()
        ..id = 'task1'
        ..title = 'Buy milk'
        ..due = '2024-05-01T10:00:00Z';
      final task2 = tasks.Task()
        ..id = 'task2'
        ..title = 'Clean room';

      when(() => mockTasksResource.list(
            any(),
            showCompleted: any(named: 'showCompleted'),
          )).thenAnswer((_) async => tasks.Tasks()..items = [task1, task2]);

      final result = await taskService.listTasks();

      expect(result, contains('Pending Tasks:'));
      expect(result, contains('Buy milk [ID: task1] (Due: 2024-05-01T10:00:00Z)'));
      expect(result, contains('Clean room [ID: task2]'));
    });

    test('should return message when no tasks exist', () async {
      when(() => mockTasksResource.list(
            any(),
            showCompleted: any(named: 'showCompleted'),
          )).thenAnswer((_) async => tasks.Tasks()..items = []);

      final result = await taskService.listTasks();

      expect(result, equals('No pending tasks found.'));
    });
  });

  group('TaskService - createTask', () {
    test('should return success message after creating task', () async {
      final taskToCreate = tasks.Task()
        ..title = 'Test Task'
        ..id = 'new_id';

      when(() => mockTasksResource.insert(any(), any()))
          .thenAnswer((_) async => taskToCreate);

      final result = await taskService.createTask('Test Task', notes: 'Some notes');

      expect(result, contains('Successfully created task: Test Task [ID: new_id]'));
      verify(() => mockTasksResource.insert(any(), any())).called(1);
    });
  });

  group('TaskService - completeTask', () {
    test('should update status to completed', () async {
      final existingTask = tasks.Task()
        ..id = 'task_id'
        ..title = 'Do work'
        ..status = 'needsAction';

      when(() => mockTasksResource.get(any(), any()))
          .thenAnswer((_) async => existingTask);
      when(() => mockTasksResource.update(any(), any(), any()))
          .thenAnswer((_) async => existingTask);

      final result = await taskService.completeTask('task_id');

      expect(result, contains('Task task_id marked as completed.'));
      expect(existingTask.status, equals('completed'));
    });
  });

  group('TaskService - deleteTask', () {
    test('should call delete on resource', () async {
      when(() => mockTasksResource.delete(any(), any()))
          .thenAnswer((_) async => null);

      final result = await taskService.deleteTask('task_id');

      expect(result, contains('Task task_id deleted successfully.'));
      verify(() => mockTasksResource.delete(any(), 'task_id')).called(1);
    });
  });
}
