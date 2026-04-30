import 'package:googleapis/tasks/v1.dart' as tasks;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

class TaskService {
  final tasks.TasksApi _tasksApi;

  TaskService(this._tasksApi);

  static Future<TaskService?> create(GoogleSignIn? googleSignIn) async {
    if (googleSignIn == null) return null;

    final httpClient = await googleSignIn.authenticatedClient();
    if (httpClient == null) return null;

    return TaskService(tasks.TasksApi(httpClient));
  }

  Future<String> listTasks({String tasklist = '@default'}) async {
    try {
      final taskListRes = await _tasksApi.tasks.list(tasklist, showCompleted: false);
      
      if (taskListRes.items == null || taskListRes.items!.isEmpty) {
        return "No pending tasks found.";
      }

      final buffer = StringBuffer("Pending Tasks:\n");
      for (var task in taskListRes.items!) {
        buffer.writeln("- ${task.title} [ID: ${task.id}]${task.due != null ? " (Due: ${task.due})" : ""}");
      }
      return buffer.toString();
    } catch (e) {
      return "Failed to list tasks: $e";
    }
  }

  Future<String> createTask(String title, {String notes = "", String? due, String tasklist = '@default'}) async {
    try {
      final task = tasks.Task()
        ..title = title
        ..notes = notes;

      if (due != null && due.isNotEmpty) {
        task.due = DateTime.parse(due).toUtc().toIso8601String();
      }

      final createdTask = await _tasksApi.tasks.insert(task, tasklist);
      return "Successfully created task: ${createdTask.title} [ID: ${createdTask.id}]";
    } catch (e) {
      return "Failed to create task: $e";
    }
  }

  Future<String> completeTask(String taskId, {String tasklist = '@default'}) async {
    try {
      final task = await _tasksApi.tasks.get(tasklist, taskId);
      task.status = 'completed';
      await _tasksApi.tasks.update(task, tasklist, taskId);
      return "Task $taskId marked as completed.";
    } catch (e) {
      return "Failed to complete task: $e";
    }
  }

  Future<String> deleteTask(String taskId, {String tasklist = '@default'}) async {
    try {
      await _tasksApi.tasks.delete(tasklist, taskId);
      return "Task $taskId deleted successfully.";
    } catch (e) {
      return "Failed to delete task: $e";
    }
  }
}
